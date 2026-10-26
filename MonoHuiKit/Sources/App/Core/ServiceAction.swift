import Foundation

struct ServiceAction {
    let id: String
    let menuName: String
    let bundleIdentifier: String
    let acceptedFileTypes: [String]
    let launchArgs: [String]

    var workflowFileName: String { "\(menuName).workflow" }
}
