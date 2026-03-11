# InfiNote iPadOS 工程藍圖（可落地）

## A. 技術架構總覽
- 平台：iPadOS 17+
- UI：`SwiftUI`（導覽、設定、列表、匯入匯出） + `UIKit`（低延遲編輯器）
- 繪圖：`UIKit Touches + CoreGraphics`，保留 `Metal` 升級點（V3）
- 資料：`SwiftData`（中繼資料）+ 檔案系統（筆跡 blob / 縮圖 / PDF）
- 文件：`FileManager`、`UIDocumentPickerViewController`、`UniformTypeIdentifiers`
- PDF：`PDFKit`（匯入、預覽）+ `UIGraphicsPDFRenderer`（匯出）
- 同步：
  - iCloud：`iCloud Drive + NSFileCoordinator + NSMetadataQuery`
  - Google Drive：MVP 先用 Document Picker；V2 再加 REST API
- Undo：`UndoManager` + CommandStack（領域操作）

### SwiftUI / UIKit 分工
- SwiftUI：Home、Folder/Notebook 管理、字型管理、同步設定、分享/匯出設定。
- UIKit：CanvasViewController、手寫輸入擷取、套索、命中測試、分塊渲染。

### iPadOS 能力與限制
- 可用（Apple Pencil）：`force`、`altitudeAngle`、`azimuthAngle`、`predictedTouches`。
- 受限：
  - 非 Apple Pencil 大多無完整壓力與傾斜。
  - Palm rejection 主要由系統決定，App 無法完全自訂。
  - 「筆尖/橡皮端切換」非所有硬體可用，需 capability 檢查與工具列備援。

## B. 模組拆分
- DrawingEngine：處理 sample -> stroke segment -> raster/vector。
- CanvasEngine：viewport、世界座標、平移縮放、分塊載入。
- BrushSystem：筆刷參數、壓感曲線、平滑策略。
- ObjectModel：Stroke/Text/Image/PDFLayer 共通 transform、zIndex、hit bounds。
- SelectionLasso：多物件選取、命中測試、群組變形。
- NotebookManagement：Folder/Notebook/Page CRUD、縮圖、索引。
- ImportExport：PDF 匯入、PDF/圖片/RTF/.note 匯出。
- SyncCore：本地變更記錄、隊列、衝突標記、同步狀態。
- CloudAdapters：iCloudAdapter / GoogleDriveAdapter。
- FontImport：TTF/OTF 匯入、註冊、字型可用性檢查。
- ShareService：UIActivityViewController、Mail、Print、Finder 檔案共享。
- UndoRedo：Command + transaction 邊界。
- Settings：工具預設、同步策略、效能參數。

## C. 資料模型設計

### 關聯圖（簡）
`Folder 1..n Notebook 1..n Page 1..n {Stroke|TextObject|ImageObject}`

### 實體（建議 SwiftData）
- Folder
  - `id: UUID`
  - `name: String`
  - `parentFolderID: UUID?`
  - `createdAt, updatedAt: Date`
- Notebook
  - `id: UUID`
  - `folderID: UUID?`
  - `title: String`
  - `coverStyle: String`
  - `createdAt, updatedAt: Date`
- Page
  - `id: UUID`
  - `notebookID: UUID`
  - `index: Int`
  - `templateID: UUID?`
  - `contentBlobPath: String`
  - `thumbnailPath: String?`
  - `updatedAt: Date`
- Stroke
  - `id: UUID`
  - `pageID: UUID`
  - `brushStyleID: UUID`
  - `bbox: SIMD4<Float>`
  - `pointCount: Int`
  - `blobPath: String`
  - `isDeleted: Bool`
- BrushStyle
  - `id: UUID`
  - `type: String`
  - `rgba: SIMD4<Float>`
  - `size: Float`
  - `opacity: Float`
  - `pressureCurve: Data`
  - `smoothing: Float`
- TextObject
  - `id: UUID`
  - `pageID: UUID`
  - `text: String`
  - `rect: CGRect`
  - `fontPSName: String`
  - `fontSize: Float`
  - `color: SIMD4<Float>`
  - `alignment: Int`
  - `transformData: Data`
- ImageObject
  - `id: UUID`
  - `pageID: UUID`
  - `imagePath: String`
  - `rect: CGRect`
  - `transformData: Data`
- PDFDocumentResource
  - `id: UUID`
  - `notebookID: UUID`
  - `pdfPath: String`
  - `pageMapData: Data`
- ExportTask
  - `id: UUID`
  - `notebookID: UUID`
  - `format: String`
  - `optionsData: Data`
  - `status: String`
  - `outputPath: String?`
- SyncMetadata
  - `id: UUID`
  - `ownerType: String`
  - `ownerID: UUID`
  - `provider: String`
  - `remoteID: String?`
  - `versionToken: String?`
  - `lastSyncedAt: Date?`
  - `conflictFlag: Bool`
- UserSettings
  - `id: UUID`
  - `onlyDrawWithPencil: Bool`
  - `autosaveIntervalSec: Int`
  - `icloudEnabled: Bool`
  - `googleDriveEnabled: Bool`
  - `defaultBrushID: UUID?`

## D. 畫布與筆跡資料結構
- 世界座標：`Float` 為主，單位 point，原點可在初次進入時置中。
- Viewport：`scale + translation`，所有輸入先 `view -> world`。
- Layer 分離：
  - TemplateLayer（橫格/方格/點陣，可調顏色/透明/間距）
  - ContentLayer（stroke/text/image/pdf）
  - OverlayLayer（lasso、選取框、游標）
- Stroke point 格式：`x,y,time,pressure,altitude,azimuth`。
- 儲存策略：
  - 活躍筆畫在記憶體 buffer。
  - 完成筆畫以 chunk 寫入 blob（每頁多檔或單檔 append）。
- 大型筆記優化：
  - spatial hash / R-tree 做可見區查詢。
  - CATiledLayer 或自建 tile cache。
  - 低縮放 LOD 抽樣（每 N 點畫一點）。
  - 背景序列化、主執行緒僅做輸入與 compositing。

## E. 互動流程與頁面規劃
- 首頁/資料夾頁：建立資料夾、建立筆記本、匯入 PDF。
- 筆記本列表：顯示縮圖、最後編輯時間、同步狀態。
- 編輯器：
  - 工具列（筆/橡皮/套索/文字）
  - 右側 Inspector（筆刷、模板、字型）
  - 底層 autosave / sync 狀態條
- 匯入管理頁：PDF 批次匯入進度、失敗重試。
- 匯出設定頁：PDF 紙張/邊距/密碼、圖片解析度、RTF。
- 字型管理頁：匯入 TTF/OTF、檢視 PostScript name、啟停。
- 雲端同步設定頁：iCloud/Drive 開關、儲存空間、衝突策略。
- 分享頁：活動面板、Mail、列印、檔案共享。

## F. 難點與風險分析
- Infinite canvas 效能：大量物件會拖慢 hit-test。
  - 解法：空間索引 + tile + LOD。
- 非 Apple Pencil 限制：壓感與傾斜不穩。
  - 解法：降級為固定壓力，UI 告知。
- Palm rejection 可控度有限。
  - 解法：提供「僅 Pencil 繪製」選項。
- Google Drive API：token/配額/背景同步限制。
  - 解法：MVP 用 Files Picker，V2 才做 SDK。
- 字型匯入：需安全範圍授權與註冊失敗處理。
  - 解法：保存到 App Support 後 `CTFontManagerRegisterFontsForURL`。
- PDF 匯出效能：高頁數與向量/光柵混排耗時。
  - 解法：分頁背景渲染 + 進度回報 + 可取消。
- 大量套索命中：O(n) 會卡。
  - 解法：先 bbox 粗篩，再 path 精篩。

## G. MVP -> V2 -> V3 Roadmap
- MVP（8-12 週）
  - 三種筆刷、stroke eraser、lasso 基礎、文字框、PDF 匯入/匯出、iCloud Drive 文件同步。
- V2（6-8 週）
  - object eraser、手寫轉文字、模板自訂、Google Drive API、衝突視覺化。
- V3（8-12 週）
  - Metal renderer、多人協作（CRDT/OT）、公開連結服務、進階筆刷（鋼筆/毛筆）。

## H. 專案目錄結構
```text
InfiNote/
├─ App/
├─ Core/
│  ├─ Canvas/
│  ├─ Input/
│  ├─ Brush/
│  ├─ Selection/
│  └─ UndoRedo/
├─ Features/
│  ├─ Home/
│  ├─ Editor/
│  ├─ Import/
│  ├─ Export/
│  ├─ FontManager/
│  └─ SyncSettings/
├─ Models/
├─ Services/
│  ├─ PDF/
│  ├─ Export/
│  ├─ Sync/
│  ├─ Share/
│  └─ Font/
├─ Storage/
├─ Resources/
└─ Tests/
```

## I. 關鍵 API 建議
- 輸入：`touchesBegan/Moved/Ended`, `coalescedTouches`, `predictedTouches`
- Pencil：`UITouch.type == .pencil`, `force`, `altitudeAngle`, `azimuthAngle(in:)`
- 手勢：`UIPanGestureRecognizer`, `UIPinchGestureRecognizer`
- PDF：`PDFDocument`, `UIGraphicsPDFRenderer`
- 字型：`CTFontManagerRegisterFontsForURL`
- iCloud 文件：`FileManager.url(forUbiquityContainerIdentifier:)`, `NSFileCoordinator`
- 分享/列印：`UIActivityViewController`, `UIPrintInteractionController`
- Finder 檔案共享：`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`

## J. 上架與可行性結論
- 可做且可上架：手寫、PDF 匯入匯出、iCloud Drive、Files 整合、字型匯入。
- 需明確限制：非 Apple Pencil 壓感/傾斜、完全可控 palm rejection、Drive 即時雙向同步。
- 第三方依賴建議：
  - 優先不用第三方渲染套件。
  - Google Drive 如需深度同步才引入 `GoogleSignIn + Drive REST`，風險是 token/審核/維護成本。
