import Flutter
import UIKit
import PDFKit
import CoreGraphics

@available(iOS 16.0, *)
public class LocksmithPdfPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "locksmith_pdf", binaryMessenger: registrar.messenger())
        let instance = LocksmithPdfPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "protectPdf":
            protectPdf(call: call, result: result)

        case "protectPdfWithPermissions":
            protectPdfWithPermissions(call: call, result: result)

        case "decryptPdf":
            decryptPdf(call: call, result: result)

        case "isPdfEncrypted":
            isPdfEncrypted(call: call, result: result)

        case "removePdfSecurity":
            removePdfSecurity(call: call, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func protectPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let password = args["password"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }

        protectPdfInternal(
            inputPath: inputPath,
            outputPath: outputPath,
            userPassword: password,
            ownerPassword: password,
            permissions: [],
            result: result
        )
    }

    private func protectPdfWithPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let userPassword = args["userPassword"] as? String,
              let ownerPassword = args["ownerPassword"] as? String,
              let permissions = args["permissions"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }

        protectPdfInternal(
            inputPath: inputPath,
            outputPath: outputPath,
            userPassword: userPassword,
            ownerPassword: ownerPassword,
            permissions: permissions,
            result: result
        )
    }

    private func decryptPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let password = args["password"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }

        let inputUrl = URL(fileURLWithPath: inputPath)
        let outputUrl = URL(fileURLWithPath: outputPath)

        guard let document = PDFDocument(url: inputUrl) else {
            result(FlutterError(code: "LOAD_FAILED", message: "Could not load PDF", details: nil))
            return
        }

        if document.isEncrypted {
            let success = document.unlock(withPassword: password)
            if !success {
                result(FlutterError(code: "WRONG_PASSWORD", message: "Incorrect password for PDF", details: nil))
                return
            }
        }

        // 方法：创建全新的文档并复制页面
        // 这是最彻底的移除加密信息的方法
        let newDocument = PDFDocument()

        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                newDocument.insert(page, at: i)
            }
        }

        // 如果输出文件已存在，先删除
        if FileManager.default.fileExists(atPath: outputPath) {
            do {
                try FileManager.default.removeItem(at: outputUrl)
            } catch {
                // 忽略删除错误，write可能会覆盖
            }
        }

        // 尝试写入新文档
        if newDocument.write(to: outputUrl) {
            if FileManager.default.fileExists(atPath: outputPath) {
                result(true)
                return
            }
        }

        // 备选方案：尝试使用 dataRepresentation
        guard let data = newDocument.dataRepresentation() else {
            result(FlutterError(code: "DECRYPTION_FAILED", message: "Failed to create decrypted PDF data", details: nil))
            return
        }

        do {
            try data.write(to: outputUrl)
            result(true)
        } catch {
            result(FlutterError(code: "WRITE_FAILED", message: "Failed to save decrypted PDF", details: error.localizedDescription))
        }
    }

    private func isPdfEncrypted(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }

        let inputUrl = URL(fileURLWithPath: inputPath)

        guard let document = PDFDocument(url: inputUrl) else {
            result(FlutterError(code: "LOAD_FAILED", message: "Could not load PDF", details: nil))
            return
        }

        result(document.isEncrypted)
    }

    private func removePdfSecurity(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // This is basically a "decrypt" and save.
        decryptPdf(call: call, result: result)
    }

    private func protectPdfInternal(
        inputPath: String,
        outputPath: String,
        userPassword: String,
        ownerPassword: String,
        permissions: [String],
        result: @escaping FlutterResult
    ) {
        let inputUrl = URL(fileURLWithPath: inputPath)
        let outputUrl = URL(fileURLWithPath: outputPath)

        // 验证输入文件是否存在
        guard FileManager.default.fileExists(atPath: inputPath) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "Input file does not exist: \(inputPath)", details: nil))
            return
        }

        // 验证输入文件可读
        guard FileManager.default.isReadableFile(atPath: inputPath) else {
            result(FlutterError(code: "FILE_NOT_READABLE", message: "Input file is not readable: \(inputPath)", details: nil))
            return
        }

        // 确保输出目录存在
        let outputDir = outputUrl.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            result(FlutterError(code: "CREATE_DIRECTORY_FAILED", message: "Failed to create output directory", details: error.localizedDescription))
            return
        }

        // 加载PDF文档
        guard let document = PDFDocument(url: inputUrl) else {
            result(FlutterError(code: "LOAD_FAILED", message: "Could not load PDF from: \(inputPath)", details: nil))
            return
        }

        // 如果文档已加密，尝试解锁
        // 注意：如果要重新加密一个已加密的文档，必须先解锁
        if document.isEncrypted {
            // 尝试使用空密码解锁（某些PDF可能标记为加密但实际未加密）
            var unlocked = document.unlock(withPassword: "")

            // 如果空密码不行，尝试使用提供的用户密码
            if !unlocked {
                unlocked = document.unlock(withPassword: userPassword)
            }

            // 如果还是不行，尝试使用所有者密码
            if !unlocked {
                unlocked = document.unlock(withPassword: ownerPassword)
            }

            if !unlocked {
                result(FlutterError(code: "ALREADY_ENCRYPTED", message: "Input PDF is already encrypted and cannot be unlocked with provided passwords. Cannot re-encrypt.", details: nil))
                return
            }
        }

        guard document.pageCount > 0 else {
            result(FlutterError(code: "INVALID_PDF", message: "PDF document has no pages.", details: nil))
            return
        }

        // 首先尝试不使用任何选项生成数据，确保文档本身可以生成数据表示
        guard document.dataRepresentation() != nil else {
            result(FlutterError(code: "INVALID_PDF", message: "PDF document cannot generate data representation. The PDF may be corrupted.", details: nil))
            return
        }

        // 方法1：尝试使用 PDFDocument.write(to:withOptions:)
        // 这是iOS 11.0+提供的最高级API
        var writeOptions: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: userPassword,
            .ownerPasswordOption: ownerPassword
        ]

        // 尝试写入
        if document.write(to: outputUrl, withOptions: writeOptions) {
            // 验证文件是否创建
            if FileManager.default.fileExists(atPath: outputPath) {
                result(true)
                return
            }
        }

        // 方法2：使用 dataRepresentation(options:)
        // 构建加密选项
        var options: [String: Any] = [
            kCGPDFContextUserPassword as String: userPassword,
            kCGPDFContextOwnerPassword as String: ownerPassword,
            kCGPDFContextEncryptionKeyLength as String: 256
        ]

        // 添加权限选项
        if permissions.isEmpty {
            options[kCGPDFContextAllowsPrinting as String] = true
            options[kCGPDFContextAllowsCopying as String] = true
        } else {
            options[kCGPDFContextAllowsPrinting as String] = permissions.contains("print")
            options[kCGPDFContextAllowsCopying as String] = permissions.contains("copy")
        }

        // 尝试生成加密数据
        var protectedData: Data? = document.dataRepresentation(options: options)

        // 如果失败，尝试不使用权限选项（只使用密码）
        if protectedData == nil {
            var simpleOptions: [String: Any] = [
                kCGPDFContextUserPassword as String: userPassword,
                kCGPDFContextOwnerPassword as String: ownerPassword,
                kCGPDFContextEncryptionKeyLength as String: 256
            ]
            protectedData = document.dataRepresentation(options: simpleOptions)
        }

        guard let finalData = protectedData else {
            result(FlutterError(code: "ENCRYPTION_FAILED", message: "Failed to generate encrypted PDF data with all attempted options. Input file: \(inputPath), Output file: \(outputPath). Document page count: \(document.pageCount), Is encrypted: \(document.isEncrypted)", details: nil))
            return
        }

        // 写入加密的PDF文件
        do {
            // 如果输出文件已存在，先删除
            if FileManager.default.fileExists(atPath: outputPath) {
                try FileManager.default.removeItem(at: outputUrl)
            }

            try finalData.write(to: outputUrl)

            // 验证输出文件是否成功创建
            guard FileManager.default.fileExists(atPath: outputPath) else {
                result(FlutterError(code: "WRITE_FAILED", message: "Output file was not created after write operation", details: nil))
                return
            }

            result(true)
        } catch {
            result(FlutterError(code: "WRITE_FAILED", message: "Failed to save encrypted PDF: \(error.localizedDescription)", details: error.localizedDescription))
        }
    }
}