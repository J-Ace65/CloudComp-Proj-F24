import UIKit
import AVFoundation
import MicrosoftCognitiveServicesSpeech

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var videoPlayer: AVPlayer?
    var videoLayer: AVPlayerLayer?
    var detectedTextLabel: UILabel!
    var translatedTextLabel: UILabel!
    var selectVideoButton: UIButton!
    
    let subscriptionKey = "kaODxC3mez4BIHb9rFsGE0c3jvjH5E7cjAum1tSDOw4HF13Xd1cCJQQJ99AKACYeBjFXJ3w3AAAYACOGLGXl" // Replace with your subscription key
    let serviceRegion = "eastus" // Replace with your service region
    var recognizer: SPXTranslationRecognizer?
    var pushStream: SPXPushAudioInputStream?
    var audioProcessingQueue: DispatchQueue!
    var testAudioProcessingQueue: DispatchQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        audioProcessingQueue = DispatchQueue(label: "com.audioProcessing.queue", qos: .userInitiated)
        testAudioProcessingQueue = DispatchQueue(label: "com.audioProcessing.queue", qos: .userInitiated)
    }
    
    func setupUI() {
        self.view.backgroundColor = .white
        
        detectedTextLabel = UILabel(frame: CGRect(x: 20, y: 100, width: view.frame.width - 40, height: 80))
        detectedTextLabel.textColor = .black
        detectedTextLabel.numberOfLines = 0
        detectedTextLabel.textAlignment = .center
        detectedTextLabel.text = "Detected text will appear here"
        detectedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.view.addSubview(detectedTextLabel)
        
        translatedTextLabel = UILabel(frame: CGRect(x: 20, y: view.frame.height - 150, width: view.frame.width - 40, height: 80))
        translatedTextLabel.textColor = .black
        translatedTextLabel.numberOfLines = 0
        translatedTextLabel.textAlignment = .center
        translatedTextLabel.text = "Translated text will appear here"
        translatedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.view.addSubview(translatedTextLabel)
        
        selectVideoButton = UIButton(frame: CGRect(x: view.frame.width - 100, y: 60, width: 80, height: 40))
        selectVideoButton.setTitle("Select", for: .normal)
        selectVideoButton.setTitleColor(.white, for: .normal)
        selectVideoButton.backgroundColor = .systemBlue
        selectVideoButton.layer.cornerRadius = 5
        selectVideoButton.addTarget(self, action: #selector(selectVideoButtonClicked), for: .touchUpInside)
        self.view.addSubview(selectVideoButton)
    }
    
    @objc func selectVideoButtonClicked() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.movie"]
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let mediaURL = info[.mediaURL] as? URL else {
            picker.dismiss(animated: true, completion: nil)
            updateLabels(detectedText: "Error: Invalid file selected.", translatedText: nil)
            return
        }
        
        picker.dismiss(animated: true) {
            self.playVideo(from: mediaURL)
        }
    }
    
    func playVideo(from url: URL) {
        videoLayer?.removeFromSuperlayer()
        
        videoPlayer = AVPlayer(url: url)
        videoLayer = AVPlayerLayer(player: videoPlayer)
        videoLayer?.frame = CGRect(x: 20, y: 200, width: view.frame.width - 40, height: view.frame.height - 400)
        videoLayer?.videoGravity = .resizeAspect
        self.view.layer.addSublayer(videoLayer!)
        
        extractAudio(from: url) { [weak self] audioURL in
            guard let self = self else { return }
            if let audioURL = audioURL {
                self.detectSourceLanguage(on: audioURL)
                self.startRealTimeTranslation(audioURL: audioURL)
                self.videoPlayer?.play()
            } else {
                self.updateLabels(detectedText: "Error: No audio track found.", translatedText: nil)
            }
        }
    }
    
    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("No audio track found in video.")
            completion(nil)
            return
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("tempAudio.caf")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let composition = AVMutableComposition()
        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Error: Could not create audio track.")
            completion(nil)
            return
        }
        
        do {
            try compositionAudioTrack.insertTimeRange(audioTrack.timeRange, of: audioTrack, at: .zero)
            let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
            exporter?.outputURL = outputURL
            exporter?.outputFileType = .m4a
            exporter?.exportAsynchronously {
                if exporter?.status == .completed {
                    print("Audio extraction successful.")
                    completion(outputURL)
                } else {
                    print("Error during audio extraction: \(String(describing: exporter?.error))")
                    completion(nil)
                }
            }
        } catch {
            print("Audio extraction failed: \(error.localizedDescription)")
            completion(nil)
        }
    }
    func detectSourceLanguage(on wavFileURL: URL){
        
        guard let speechConfig = try? SPXSpeechConfiguration(subscription: subscriptionKey, region: serviceRegion) else {
            updateLabels(detectedText: "Error: Invalid speech configuration.", translatedText: nil)
            return
        }
        
        pushStream = SPXPushAudioInputStream()
        guard let audioConfig = SPXAudioConfiguration(streamInput: pushStream!) else {
            updateLabels(detectedText: "Error: Failed to configure audio.", translatedText: nil)
            return
        }
        
        do {
            let autoDetectConfig  = try SPXAutoDetectSourceLanguageConfiguration(["es-ES", "fr-FR", "zh-CN", "ja-JP"])
            let speechRecognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, autoDetectSourceLanguageConfiguration: autoDetectConfig, audioConfiguration: audioConfig)
            
            testAudioProcessingQueue.async {
                self.streamAudioFromFile(url: wavFileURL)
            }
            
            let result = try speechRecognizer.recognizeOnce()
            if(result.reason == SPXResultReason.canceled){
                let reasoning = try SPXCancellationDetails(fromCanceledRecognitionResult: result)
                updateLabels(detectedText: "Error: Failed due to: " + (reasoning.errorDetails ?? "Cannot determine reason"), translatedText: nil)
                return
            }
            else if(result.reason == SPXResultReason.recognizedSpeech){
                let detectedLanguage =  SPXAutoDetectSourceLanguageResult(result)
                print("The Detected Language was: " + (detectedLanguage.language ?? "COULD NOT DETERMINE!"))
                
            }
            else{
                print("There was an error.")
            }
            
        } catch {
            updateLabels(detectedText: "Error: Failed Language Detection.", translatedText: nil)
            return
        }
    }
    
    func startRealTimeTranslation(audioURL: URL) {
        guard let speechConfig = try? SPXSpeechTranslationConfiguration(subscription: subscriptionKey, region: serviceRegion) else {
            updateLabels(detectedText: "Error: Invalid speech configuration.", translatedText: nil)
            return
        }

        speechConfig.speechRecognitionLanguage = "es-ES" // Set source language
        speechConfig.addTargetLanguage("en") // Translate to English
        
        pushStream = SPXPushAudioInputStream()
        guard let audioConfig = SPXAudioConfiguration(streamInput: pushStream!) else {
            updateLabels(detectedText: "Error: Failed to configure audio.", translatedText: nil)
            return
        }
        
        do {
            recognizer = try SPXTranslationRecognizer(speechTranslationConfiguration: speechConfig, audioConfiguration: audioConfig)
            
            recognizer?.addRecognizedEventHandler { [weak self] (_, eventArgs) in
                guard let self = self else { return }
                let detectedText = eventArgs.result.text ?? "(No text detected)"
                let translation = eventArgs.result.translations["en"] as? String ?? "(No translation)"
                self.updateLabels(detectedText: detectedText, translatedText: translation)
            }
            
            recognizer?.addCanceledEventHandler { [weak self] (_, eventArgs) in
                guard let self = self else { return }
                self.updateLabels(detectedText: "Error: Translation canceled.", translatedText: eventArgs.errorDetails)
            }
            
            audioProcessingQueue.async {
                self.streamAudioFromFile(url: audioURL)
            }
            
            try recognizer?.startContinuousRecognition()
        } catch {
            updateLabels(detectedText: "Error: Translation setup failed.", translatedText: nil)
        }
    }
    
    func streamAudioFromFile(url: URL) {
        let asset = AVAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            updateLabels(detectedText: "Error: No audio track found.", translatedText: nil)
            return
        }
        
        do {
            let reader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            reader.add(readerOutput)
            
            reader.startReading()
            let playbackStart = Date()
            
            while reader.status == .reading {
                if let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                   let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var buffer = Data(count: length)
                    buffer.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    pushStream?.write(buffer)
                    
                    // Synchronize with video playback
                    let elapsed = Date().timeIntervalSince(playbackStart)
                    let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    
                    // Allow minor overlap for faster updates
                    if sampleTime > elapsed + 1.0 { // Reduce delay threshold
                        Thread.sleep(forTimeInterval: sampleTime - elapsed - 1.0) // Smaller delay
                    }
                }
            }
            
            if reader.status == .completed {
                print("Audio streaming completed.")
            } else {
                print("Error during audio streaming: \(String(describing: reader.error))")
            }
            
            pushStream?.close()
        } catch {
            print("Error reading audio file: \(error.localizedDescription)")
            updateLabels(detectedText: "Error: Audio streaming failed.", translatedText: nil)
        }
    }



    
    func updateLabels(detectedText: String?, translatedText: String?) {
        DispatchQueue.main.async {
            self.detectedTextLabel.text = detectedText ?? "No text detected."
            self.translatedTextLabel.text = translatedText ?? "No translation available."
        }
    }
}
