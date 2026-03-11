# InfiNote MVP Roadmap（工程拆解）

## Milestone 1: 編輯器核心（第 1-3 週）
- 完成 UIKit Canvas 容器與 SwiftUI 橋接。
- Pencil/touch sample 收集與基礎筆刷渲染。
- viewport 平移縮放與模板背景。
- 自動存檔（debounce + 背景序列化）。

## Milestone 2: 物件與操作（第 4-6 週）
- stroke eraser、lasso 選取/移動/刪除。
- 文字方塊（建立、拖曳、屬性編輯）。
- Undo/Redo command stack。

## Milestone 3: 文件流程（第 7-9 週）
- PDF 匯入（單檔與批次）。
- PDF 匯出（紙張、邊距、密碼）。
- 圖片匯出與 RTF 匯出。

## Milestone 4: 雲端與上線（第 10-12 週）
- iCloud Drive 同步（文件型）
- 錯誤復原、衝突提示、離線快取。
- 測試與效能壓測（10k strokes）。
- TestFlight 內測。

## 交付標準
- 書寫/縮放穩定 60fps（近代 iPad）。
- 10k strokes 可操作（平移/縮放/選取）。
- 異常關閉後可恢復最近內容。
