import AVFoundation
import Foundation

#if os(iOS) || os(tvOS) || os(macOS)
/// An object that provides the interface to control the AVCaptureDevice's transport behavior.
@available(tvOS 17.0, *)
public class IOVideoCaptureUnit: IOCaptureUnit {
    /// The default videoSettings for a device.
    public static let defaultVideoSettings: [NSString: AnyObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]

    typealias Output = AVCaptureVideoDataOutput

    /// The current video device object.
    public private(set) var device: AVCaptureDevice?
    var input: AVCaptureInput?
    var output: Output? {
        didSet {
            output?.alwaysDiscardsLateVideoFrames = true
            output?.videoSettings = IOVideoCaptureUnit.defaultVideoSettings as [String: Any]
        }
    }
    var connection: AVCaptureConnection?

    #if os(iOS) || os(macOS)
    /// Specifies the videoOrientation indicates whether to rotate the video flowing through the connection to a given orientation.
    public var videoOrientation: AVCaptureVideoOrientation = .portrait {
        didSet {
            output?.connections.filter { $0.isVideoOrientationSupported }.forEach {
                $0.videoOrientation = videoOrientation
            }
        }
    }
    #endif

    /// Spcifies the video mirroed indicates whether the video flowing through the connection should be mirrored about its vertical axis.
    public var isVideoMirrored = false {
        didSet {
            output?.connections.filter { $0.isVideoMirroringSupported }.forEach {
                $0.isVideoMirrored = isVideoMirrored
            }
        }
    }

    #if os(iOS)
    /// Specifies the preferredVideoStabilizationMode most appropriate for use with the connection.
    public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off {
        didSet {
            output?.connections.filter { $0.isVideoStabilizationSupported }.forEach {
                $0.preferredVideoStabilizationMode = preferredVideoStabilizationMode
            }
        }
    }
    #endif

    func attachDevice(_ device: AVCaptureDevice?, videoUnit: IOVideoUnit) throws {
        setSampleBufferDelegate(nil)
        detachSession(videoUnit.mixer?.session)
        guard let device else {
            self.device = nil
            input = nil
            output = nil
            connection = nil
            return
        }
        self.device = device
        input = try AVCaptureDeviceInput(device: device)
        output = AVCaptureVideoDataOutput()
        #if os(iOS)
        if let output, #available(iOS 13, *), let port = input?.ports.first(where: { $0.mediaType == .video && $0.sourceDeviceType == device.deviceType && $0.sourceDevicePosition == device.position }) {
            connection = AVCaptureConnection(inputPorts: [port], output: output)
        } else {
            connection = nil
        }
        #else
        if let output, let port = input?.ports.first(where: { $0.mediaType == .video }) {
            connection = AVCaptureConnection(inputPorts: [port], output: output)
        } else {
            connection = nil
        }
        #endif
        attachSession(videoUnit.mixer?.session)
        output?.connections.forEach {
            if $0.isVideoMirroringSupported {
                $0.isVideoMirrored = isVideoMirrored
            }
            #if !os(tvOS)
            if $0.isVideoOrientationSupported {
                $0.videoOrientation = videoOrientation
            }
            #endif
            #if os(iOS)
            if $0.isVideoStabilizationSupported {
                $0.preferredVideoStabilizationMode = preferredVideoStabilizationMode
            }
            #endif
        }
        setSampleBufferDelegate(videoUnit)
    }

    #if os(macOS)
    func attachScreen(_ screen: AVCaptureScreenInput?, videoUnit: IOVideoUnit) {
        setSampleBufferDelegate(nil)
        detachSession(videoUnit.mixer?.session)
        device = nil
        input = screen
        output = AVCaptureVideoDataOutput()
        connection = nil
        attachSession(videoUnit.mixer?.session)
        setSampleBufferDelegate(videoUnit)
    }
    #endif

    func setFrameRate(_ frameRate: Float64) {
        guard let device else {
            return
        }
        do {
            try device.lockForConfiguration()
            if device.activeFormat.isFrameRateSupported(frameRate) {
                device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
            } else {
                if let format = device.videoFormat(
                    width: device.activeFormat.formatDescription.dimensions.width,
                    height: device.activeFormat.formatDescription.dimensions.height,
                    frameRate: frameRate,
                    isMultiCamSupported: device.activeFormat.isMultiCamSupported
                ) {
                    device.activeFormat = format
                    device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                }
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("while locking device for fps:", error)
        }
    }

    func setTorchMode(_ torchMode: AVCaptureDevice.TorchMode) {
        guard let device, device.isTorchModeSupported(torchMode) else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchMode
            device.unlockForConfiguration()
        } catch {
            logger.error("while setting torch:", error)
        }
    }

    func setSampleBufferDelegate(_ videoUnit: IOVideoUnit?) {
        if let videoUnit {
            #if !os(tvOS)
            videoOrientation = videoUnit.videoOrientation
            #endif
            setFrameRate(videoUnit.frameRate)
        }
        output?.setSampleBufferDelegate(videoUnit, queue: videoUnit?.lockQueue)
    }
}
#endif
