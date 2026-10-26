import Foundation

enum ModuleRegistry {
    static let allActions: [ServiceAction] =
        CompressModule.serviceActions + VideoCompressModule.serviceActions
        + DateFolderModule.serviceActions + QuickRenameModule.serviceActions + ShelfModule.serviceActions
}
