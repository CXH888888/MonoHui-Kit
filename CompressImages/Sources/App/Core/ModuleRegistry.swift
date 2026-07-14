import Foundation

enum ModuleRegistry {
    static let allActions: [ServiceAction] =
        CompressModule.serviceActions + DateFolderModule.serviceActions
}
