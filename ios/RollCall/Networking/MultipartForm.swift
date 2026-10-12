//
//  MultipartForm.swift
//  RollCall
//
//  Builds a "multipart/form-data" request body: the standard way to send
//  text fields AND a file in one upload (it's what a web form with a file
//  picker sends). Each part is separated by a unique "boundary" line.
//

import Foundation

struct MultipartForm {
    let boundary = "RollCall-\(UUID().uuidString)"
    private var body = Data()

    /// The value for the request's Content-Type header.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// The finished body, with the closing boundary added.
    func finished() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}
