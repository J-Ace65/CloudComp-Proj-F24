import UIKit
import AVFoundation
import PhotosUI
import MicrosoftCognitiveServicesSpeech

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var videoPlayer: AVPlayer?
    var videoLayer: AVPlayerLayer?
    var detectedTextLabel: UILabel!
    var translatedTextLabel: UILabel!
    var selectVideoButton: UIButton!
    
    var sub: String!
    var region: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sub = "YourSubKey"
        region = "YourServiceRegion"
        
        setupUI()
    }
    
    func setupUI() {
        self.view.backgroundColor = .white
        
        // Detected text label (top)
        detectedTextLabel = UILabel(frame: CGRect(x: 20, y: 130, width: view.frame.width - 40, height: 80))
        detectedTextLabel.textColor = .black
        detectedTextLabel.numberOfLines = 0
        detectedTextLabel.textAlignment = .center
        detectedTextLabel.text = "Detected text will appear here"
        detectedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.view.addSubview(detectedTextLabel)
        
        // Translated text label (bottom, spaced appropriately)
        translatedTextLabel = UILabel(frame: CGRect(x: 20, y: view.frame.height - 240, width: view.frame.width - 40, height: 80))
        translatedTextLabel.textColor = .black
        translatedTextLabel.numberOfLines = 0
        translatedTextLabel.textAlignment = .center
        translatedTextLabel.text = "Translated text will appear here"
        translatedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.view.addSubview(translatedTextLabel)
        
        // Select video button (top-right)
        selectVideoButton = UIButton(frame: CGRect(x: view.frame.width - 100, y: 60, width: 80, height: 40))
        selectVideoButton.setTitle("Select", for: .normal)
        selectVideoButton.setTitleColor(.white, for: .normal)
        selectVideoButton.backgroundColor = .systemBlue
        selectVideoButton.layer.cornerRadius = 5
        selectVideoButton.addTarget(self, action: #selector(selectVideoButtonClicked), for: .touchUpInside)
        self.view.addSubview(selectVideoButton)
    }
    
    @objc func selectVideoButtonClicked() {
        // Open Photos app for video selection
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.movie"]
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let mediaURL = info[.mediaURL] as? URL else {
            picker.dismiss(animated: true, completion: nil)
            return
        }
        picker.dismiss(animated: true) {
            self.playVideo(from: mediaURL)
        }
    }
    
    func playVideo(from url: URL) {
        // Remove existing video layer if present
        videoLayer?.removeFromSuperlayer()
        
        // Setup video player
        videoPlayer = AVPlayer(url: url)
        videoLayer = AVPlayerLayer(player: videoPlayer)
        videoLayer?.frame = CGRect(x: 20, y: 150, width: view.frame.width - 40, height: view.frame.height - 350)
        videoLayer?.videoGravity = .resizeAspect
        self.view.layer.addSublayer(videoLayer!)
        
        // Play the video
        videoPlayer?.play()
        
        // Start extracting audio and translating
        extractAudio(from: url) { audioURL in
            guard let audioURL = audioURL else {
                self.updateLabels(detectedText: "Audio extraction failed.", translatedText: nil)
                return
            }
            self.translateAudio(from: audioURL)
        }
    }
    
    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio.wav")
        
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(nil)
            return
        }
        
        exporter.outputFileType = .wav
        exporter.outputURL = outputURL
        
        exporter.exportAsynchronously {
            if exporter.status == .completed {
                completion(outputURL)
            } else {
                completion(nil)
            }
        }
    }
    
    func translateAudio(from audioURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let speechConfig = try? SPXSpeechTranslationConfiguration(subscription: self.sub, region: self.region) else {
                    print("Error: Failed to create SPXSpeechTranslationConfiguration")
                    self.updateLabels(detectedText: "Speech config error.", translatedText: nil)
                    return
                }
                
                speechConfig.speechRecognitionLanguage = "en"
                
                guard let audioConfig = try? SPXAudioConfiguration(wavFileInput: audioURL.path) else {
                    print("Error: Failed to create audio configuration")
                    self.updateLabels(detectedText: "Audio config error.", translatedText: nil)
                    return
                }
                
                let translator = try SPXTranslationRecognizer(speechTranslationConfiguration: speechConfig, audioConfiguration: audioConfig)
                
                translator.addRecognizingEventHandler { _, evt in
                    DispatchQueue.main.async {
                        self.detectedTextLabel.text = evt.result.text
                    }
                }
                
                let result = try translator.recognizeOnce()
                let translationDictionary = result.translations
                let translationResult = translationDictionary["en"] as? String ?? "(Translation failed)"
                
                self.updateLabels(detectedText: result.text, translatedText: translationResult)
            } catch {
                print("Error during translation: \(error)")
                self.updateLabels(detectedText: "Translation failed.", translatedText: nil)
            }
        }
    }
    
    func updateLabels(detectedText: String?, translatedText: String?) {
        DispatchQueue.main.async {
            if let detectedText = detectedText {
                self.detectedTextLabel.text = detectedText
            }
            if let translatedText = translatedText {
                self.translatedTextLabel.text = translatedText
            }
        }
    }
}
