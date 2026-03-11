import Foundation

protocol Command {
    var name: String { get }
    func execute()
    func undo()
}

final class CommandStack {
    private(set) var undoStack: [Command] = []
    private(set) var redoStack: [Command] = []

    func run(_ command: Command) {
        command.execute()
        undoStack.append(command)
        redoStack.removeAll()
    }

    func undo() {
        guard let cmd = undoStack.popLast() else { return }
        cmd.undo()
        redoStack.append(cmd)
    }

    func redo() {
        guard let cmd = redoStack.popLast() else { return }
        cmd.execute()
        undoStack.append(cmd)
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
