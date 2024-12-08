import UIKit
import AVFoundation
import MicrosoftCognitiveServicesSpeech

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    // Variables for managing video playback
    var videoPlayer: AVPlayer? // The player for video playback
    var videoLayer: AVPlayerLayer? // The layer that displays the video on the screen

    // UI elements for displaying detected and translated text
    var detectedTextLabel: UILabel! // Label to show detected speech from the video
    var translatedTextLabel: UILabel! // Label to show translated speech
    var selectVideoButton: UIButton! // Button to allow user to select a video

    // Playback control buttons
    var playPauseButton: UIButton! // Button to play or pause the video
    var rewindButton: UIButton! // Button to rewind the video

    // Microsoft Cognitive Speech Service configuration
    let subscriptionKey = "kaODxC3mez4BIHb9rFsGE0c3jvjH5E7cjAum1tSDOw4HF13Xd1cCJQQJ99AKACYeBjFXJ3w3AAAYACOGLGXl" // Replace with your API subscription key
    let serviceRegion = "eastus" // Azure service region
    var recognizer: SPXTranslationRecognizer? // Recognizer for real-time speech translation
    var audioProcessingQueue: DispatchQueue! // Queue for handling audio processing tasks
    var sourceLanguage: String? // Detected language of the audio

    // To store detected and translated speech segments with timestamps
    var speechSegments: [(start: TimeInterval, end: TimeInterval, detectedText: String, translatedText: String)] = []

    // Loading overlay for displaying a "processing" indicator
    var loadingOverlay: UIView? // Overlay shown when the app is busy (e.g., processing audio)

    // Function to show a loading overlay on the screen
    func showLoading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.loadingOverlay != nil {
                return
            }

            let overlay = UIView(frame: self.view.bounds)
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)

            let activityIndicator = UIActivityIndicatorView(style: .large)
            activityIndicator.center = overlay.center
            activityIndicator.startAnimating()
            overlay.addSubview(activityIndicator)

            self.view.addSubview(overlay)
            self.loadingOverlay = overlay
        }
    }

    // Function to hide the loading overlay
    func hideLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingOverlay?.removeFromSuperview()
            self?.loadingOverlay = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        audioProcessingQueue = DispatchQueue(label: "com.audioProcessing.queue", qos: .userInitiated)

        Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateDisplayedText), userInfo: nil, repeats: true)
    }

    func setupUI() {
        // Set the main background color
        self.view.backgroundColor = UIColor(red: 42/255, green: 47/255, blue: 60/255, alpha: 1.0)
        
        // Create a header area
        let headerColor = UIColor(red: 50/255, green: 55/255, blue: 70/255, alpha: 1.0)
        let headerHeight: CGFloat = 120
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: headerHeight))
        headerView.backgroundColor = headerColor
        self.view.addSubview(headerView)
        
        // Add an app title with gradient effect
        let appTitleLabel = UILabel(frame: CGRect(x: 20, y: 60, width: view.frame.width - 140, height: 40))
        appTitleLabel.text = "AudioLens" // App title
        appTitleLabel.textColor = .white
        appTitleLabel.textAlignment = .left
        appTitleLabel.font = UIFont.boldSystemFont(ofSize: 28)

        // Apply a gradient to the app title
        let gradient = CAGradientLayer()
        gradient.frame = appTitleLabel.bounds
        gradient.colors = [UIColor.systemPurple.cgColor, UIColor.systemBlue.cgColor, UIColor.systemTeal.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)

        // Create a gradient mask for the text
        let gradientMask = UILabel(frame: appTitleLabel.bounds)
        gradientMask.text = appTitleLabel.text
        gradientMask.font = appTitleLabel.font
        gradientMask.textAlignment = appTitleLabel.textAlignment
        gradientMask.textColor = .black
        gradient.mask = gradientMask.layer
        appTitleLabel.layer.addSublayer(gradient)
        appTitleLabel.layer.shadowColor = UIColor.black.cgColor // Add shadow to the text
        appTitleLabel.layer.shadowOffset = CGSize(width: 1, height: 1)
        appTitleLabel.layer.shadowOpacity = 0.5
        appTitleLabel.layer.shadowRadius = 2

        headerView.addSubview(appTitleLabel)

        // Add a "Select Video" button in the header
        selectVideoButton = UIButton(frame: CGRect(x: view.frame.width - 140, y: 60, width: 130, height: 40))
        selectVideoButton.setTitle("Select Video...", for: .normal)
        selectVideoButton.setTitleColor(.white, for: .normal)
        selectVideoButton.backgroundColor = .systemBlue
        selectVideoButton.layer.cornerRadius = 5
        selectVideoButton.addTarget(self, action: #selector(selectVideoButtonClicked), for: .touchUpInside)
        headerView.addSubview(selectVideoButton)

        // Add a divider line below the header
        let dividerLine = UIView(frame: CGRect(x: 0, y: headerHeight, width: view.frame.width, height: 1))
        dividerLine.backgroundColor = UIColor(red: 27/255, green: 31/255, blue: 42/255, alpha: 1.0)
        self.view.addSubview(dividerLine)
        
        // Set up a section for "Detected Text"
        let detectedTextTitle = UILabel(frame: CGRect(x: 20, y: headerHeight + 40, width: view.frame.width - 40, height: 30))
        detectedTextTitle.text = "Detected Text"
        detectedTextTitle.textColor = .white
        detectedTextTitle.textAlignment = .center
        detectedTextTitle.font = UIFont.boldSystemFont(ofSize: 18)
        self.view.addSubview(detectedTextTitle)

        let detectedTextBox = UIView(frame: CGRect(x: 20, y: headerHeight + 80, width: view.frame.width - 40, height: 140))
        detectedTextBox.backgroundColor = UIColor(red: 27/255, green: 31/255, blue: 42/255, alpha: 1.0)
        detectedTextBox.layer.cornerRadius = 10
        self.view.addSubview(detectedTextBox)

        detectedTextLabel = UILabel(frame: CGRect(x: 10, y: 10, width: detectedTextBox.frame.width - 20, height: detectedTextBox.frame.height - 20))
        detectedTextLabel.textColor = .white
        detectedTextLabel.numberOfLines = 0
        detectedTextLabel.textAlignment = .center
        detectedTextLabel.text = "Detected text will appear here"
        detectedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        detectedTextBox.addSubview(detectedTextLabel)

        // Set up a section for "Translated Text"
        let translatedTextBox = UIView(frame: CGRect(x: 20, y: view.frame.height - 230, width: view.frame.width - 40, height: 140))
        translatedTextBox.backgroundColor = UIColor(red: 27/255, green: 31/255, blue: 42/255, alpha: 1.0)
        translatedTextBox.layer.cornerRadius = 10
        self.view.addSubview(translatedTextBox)

        translatedTextLabel = UILabel(frame: CGRect(x: 10, y: 10, width: translatedTextBox.frame.width - 20, height: translatedTextBox.frame.height - 20))
        translatedTextLabel.textColor = .white
        translatedTextLabel.numberOfLines = 0
        translatedTextLabel.textAlignment = .center
        translatedTextLabel.text = "Translated text will appear here"
        translatedTextLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        translatedTextBox.addSubview(translatedTextLabel)

        let translatedTextTitle = UILabel(frame: CGRect(x: 20, y: view.frame.height - 80, width: view.frame.width - 40, height: 30))
        translatedTextTitle.text = "Translated Text"
        translatedTextTitle.textColor = .white
        translatedTextTitle.textAlignment = .center
        translatedTextTitle.font = UIFont.boldSystemFont(ofSize: 18)
        self.view.addSubview(translatedTextTitle)
        
        // Display a center message while awaiting video selection
        let centerMessageLabel = UILabel(frame: CGRect(x: 20, y: view.frame.height / 2, width: view.frame.width - 40, height: 100))
        centerMessageLabel.text = "Awaiting video selection..."
        centerMessageLabel.textColor = .white
        centerMessageLabel.textAlignment = .center
        centerMessageLabel.numberOfLines = 0
        centerMessageLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        self.view.addSubview(centerMessageLabel)

        setupPlaybackControls()
    }

    func setupPlaybackControls() {
        // Playback controls container
        let controlsContainer = UIView(frame: CGRect(x: 20, y: view.frame.height - 317, width: view.frame.width - 40, height: 60))
        controlsContainer.backgroundColor = UIColor(red: 210/255, green: 90/255, blue: 120/255, alpha: 1.0)
        controlsContainer.layer.cornerRadius = 10
        controlsContainer.isHidden = true // Initially hidden
        controlsContainer.tag = 999 // Tag to identify the container later
        self.view.addSubview(controlsContainer)
        
        // Centered "Playback Controls" label
        let controlsLabel = UILabel(frame: CGRect(x: 0, y: 0, width: controlsContainer.frame.width, height: 30))
        controlsLabel.center = CGPoint(x: controlsContainer.frame.width / 2, y: controlsContainer.frame.height / 2)
        controlsLabel.text = "Time Travel Console"
        controlsLabel.textAlignment = .center
        controlsLabel.font = UIFont.boldSystemFont(ofSize: 16)
        controlsLabel.textColor = .white
        controlsContainer.addSubview(controlsLabel)
        
        // Play/Pause button
        playPauseButton = UIButton(frame: CGRect(x: 20, y: 10, width: 40, height: 40))
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(playPauseButtonClicked), for: .touchUpInside)
        controlsContainer.addSubview(playPauseButton)

        // Rewind button
        rewindButton = UIButton(frame: CGRect(x: controlsContainer.frame.width - 60, y: 10, width: 40, height: 40))
        rewindButton.setImage(UIImage(systemName: "gobackward"), for: .normal)
        rewindButton.tintColor = .white
        rewindButton.addTarget(self, action: #selector(rewindButtonClicked), for: .touchUpInside)
        controlsContainer.addSubview(rewindButton)
    }

    @objc func playPauseButtonClicked() {
        guard let player = videoPlayer else { return }
        if player.timeControlStatus == .paused {
            player.play()
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        } else {
            player.pause()
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
    }

    @objc func rewindButtonClicked() {
        guard let player = videoPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let rewindTime = max(currentTime - 10, 0) // Rewind 10 seconds or to the start
        player.seek(to: CMTime(seconds: rewindTime, preferredTimescale: 600))
    }
    @objc func selectVideoButtonClicked() {
        // Open the photo library to let the user select a video
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.movie"] // Allow video selection only
        self.present(imagePicker, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        // Handle the selected video
        guard let mediaURL = info[.mediaURL] as? URL else {
            picker.dismiss(animated: true, completion: nil)
            updateLabels(detectedText: "Error: Invalid file selected.", translatedText: nil)
            return
        }
        picker.dismiss(animated: true) {
            self.playVideo(from: mediaURL) // Play the selected video
        }
    }

    func showPlaybackControls() {
        // Find the playback controls container by its tag and unhide it
        if let controlsContainer = self.view.viewWithTag(999) {
            controlsContainer.isHidden = false
        }
    }

    func playVideo(from url: URL) {
        // Remove any existing video layer
        videoLayer?.removeFromSuperlayer()

        // Initialize the video player with the selected file
        videoPlayer = AVPlayer(url: url)
        videoLayer = AVPlayerLayer(player: videoPlayer)
        videoLayer?.frame = CGRect(x: 20, y: 225, width: view.frame.width - 40, height: view.frame.height - 400)
        videoLayer?.videoGravity = .resizeAspect
        self.view.layer.addSublayer(videoLayer!) // Add the video layer to the screen

        // Extract audio from the video and start processing
        extractAudio(from: url) { [weak self] audioURL in
            guard let self = self else { return }
            if let audioURL = audioURL {
                self.detectSourceLanguage(on: audioURL) { detectedLanguage in
                    guard let detectedLanguage = detectedLanguage else {
                        self.updateLabels(detectedText: "Error: Language detection failed.", translatedText: nil)
                        return
                    }
                    self.startRealTimeTranslation(audioURL: audioURL, sourceLanguage: detectedLanguage)
                    self.videoPlayer?.play() // Play the video once setup is complete
                    self.showPlaybackControls() // Show the playback controls
                }
            } else {
                self.updateLabels(detectedText: "Error: No audio track found.", translatedText: nil)
            }
        }
    }

    
    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        // Load the video as an AVAsset
        let asset = AVAsset(url: videoURL)

        // Check if the video has an audio track
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("No audio track found in video.") // Log if no audio is found
            completion(nil)
            return
        }
        
        // Set up a temporary file for the extracted audio
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("tempAudio.caf")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL) // Remove existing file if needed
        }
        
        // Create a composition for processing the audio
        let composition = AVMutableComposition()
        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Error: Could not create audio track.") // Log if track creation fails
            completion(nil)
            return
        }
        
        do {
            // Add the audio track to the composition
            try compositionAudioTrack.insertTimeRange(audioTrack.timeRange, of: audioTrack, at: .zero)
            
            // Set up an exporter to save the audio as an .m4a file
            let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
            exporter?.outputURL = outputURL
            exporter?.outputFileType = .m4a
            exporter?.exportAsynchronously {
                if exporter?.status == .completed {
                    print("Audio extraction successful.") // Log success
                    completion(outputURL) // Return the extracted audio file
                } else {
                    print("Error during audio extraction: \(String(describing: exporter?.error))") // Log any errors
                    completion(nil)
                }
            }
        } catch {
            print("Audio extraction failed: \(error.localizedDescription)") // Log exceptions
            completion(nil)
        }
    }

    
    func detectSourceLanguage(on wavFileURL: URL, completion: @escaping (String?) -> Void) {
        // Show a loading overlay to indicate processing
        DispatchQueue.main.async {
            self.showLoading()
        }

        // Configure speech recognition
        guard let speechConfig = try? SPXSpeechConfiguration(subscription: subscriptionKey, region: serviceRegion) else {
            DispatchQueue.main.async {
                self.hideLoading()
            }
            updateLabels(detectedText: "Error: Invalid speech configuration.", translatedText: nil) // Log configuration issues
            completion(nil)
            return
        }

        // Create a stream for processing audio
        let tempStream = SPXPushAudioInputStream()
        guard let audioConfig = SPXAudioConfiguration(streamInput: tempStream) else {
            DispatchQueue.main.async {
                self.hideLoading()
            }
            updateLabels(detectedText: "Error: Failed to configure audio.", translatedText: nil) // Log audio configuration failure
            completion(nil)
            return
        }

        do {
            // Set up auto-detection for supported languages
            let autoDetectConfig = try SPXAutoDetectSourceLanguageConfiguration(["es-ES", "fr-FR", "zh-CN", "ja-JP"])
            let recognizer = try SPXSpeechRecognizer(
                speechConfiguration: speechConfig,
                autoDetectSourceLanguageConfiguration: autoDetectConfig,
                audioConfiguration: audioConfig
            )

            // Perform recognition on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.streamAudioFromFile(url: wavFileURL, to: tempStream) // Stream the audio to the recognizer

                // Attempt to recognize the language
                let result: SPXSpeechRecognitionResult?
                do {
                    result = try recognizer.recognizeOnce()
                } catch {
                    DispatchQueue.main.async {
                        self.hideLoading()
                        self.updateLabels(detectedText: "Error: Recognition failed.", translatedText: nil) // Log failure
                    }
                    completion(nil)
                    return
                }

                // Handle the recognition result
                DispatchQueue.main.async {
                    self.hideLoading()
                    if let result = result,
                       result.reason == SPXResultReason.recognizedSpeech,
                       let detectedLanguage = SPXAutoDetectSourceLanguageResult(result).language {
                        print("Detected Language: \(detectedLanguage)") // Log the detected language
                        completion(detectedLanguage) // Return the detected language
                    } else {
                        self.updateLabels(detectedText: "Error: Language detection failed.", translatedText: nil) // Log detection failure
                        completion(nil)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.hideLoading()
                self.updateLabels(detectedText: "Error: Failed Language Detection.", translatedText: nil) // Log exceptions
            }
            completion(nil)
        }
    }
    
    func startRealTimeTranslation(audioURL: URL, sourceLanguage: String) {
        // Configure translation recognizer
        guard let speechConfig = try? SPXSpeechTranslationConfiguration(subscription: subscriptionKey, region: serviceRegion) else {
            updateLabels(detectedText: "Error: Invalid speech configuration.", translatedText: nil)
            return
        }
        
        // Set the source language and target language (English)
        speechConfig.speechRecognitionLanguage = sourceLanguage
        speechConfig.addTargetLanguage("en-US")
        
        // Create a stream for audio input
        let translationStream = SPXPushAudioInputStream()
        guard let audioConfig = SPXAudioConfiguration(streamInput: translationStream) else {
            updateLabels(detectedText: "Error: Failed to configure audio.", translatedText: nil)
            return
        }
        
        do {
            // Initialize the recognizer with configuration and audio stream
            recognizer = try SPXTranslationRecognizer(speechTranslationConfiguration: speechConfig, audioConfiguration: audioConfig)
            
            var lastEndTime: TimeInterval = 0.0
            
            // Handle recognized text and translations
            recognizer?.addRecognizedEventHandler { [weak self] (_, eventArgs) in
                guard let self = self else { return }
                let detectedText = eventArgs.result.text ?? "(No text detected)" // Get recognized text
                let translation = eventArgs.result.translations["en"] as? String ?? "(No translation)" // Get translation
                
                // Calculate segment timing
                let duration = TimeInterval(eventArgs.result.duration) / 10_000_000
                let startTime = lastEndTime
                let endTime = startTime + duration + 2.0
                lastEndTime = endTime
                
                // Save the segment details
                self.speechSegments.append((start: startTime, end: endTime, detectedText: detectedText, translatedText: translation))
            }
            
            // Handle translation cancellation
            recognizer?.addCanceledEventHandler { [weak self] (_, eventArgs) in
                guard let self = self else { return }
                self.updateLabels(detectedText: "Error: Translation canceled.", translatedText: eventArgs.errorDetails) // Log cancellation
            }
            
            // Start streaming audio for translation
            audioProcessingQueue.async {
                self.streamAudioFromFile(url: audioURL, to: translationStream)
            }
            
            try recognizer?.startContinuousRecognition() // Begin continuous recognition
        } catch {
            updateLabels(detectedText: "Error: Translation setup failed.", translatedText: nil) // Log setup failure
        }
    }

    
    func streamAudioFromFile(url: URL, to stream: SPXPushAudioInputStream) {
        // Load the audio from the given file URL
        let asset = AVAsset(url: url)

        // Ensure the audio track exists
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            updateLabels(detectedText: "Error: No audio track found.", translatedText: nil)
            return
        }
        
        do {
            // Set up an AVAssetReader to read audio data
            let reader = try AVAssetReader(asset: asset)

            // Configure output settings for the audio (e.g., format, sample rate, etc.)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000, // Set sample rate to 16 kHz
                AVNumberOfChannelsKey: 1, // Mono audio
                AVLinearPCMBitDepthKey: 16, // 16-bit audio
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            // Add a track output for the audio
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            reader.add(readerOutput)

            // Start reading the audio data
            reader.startReading()

            while reader.status == .reading {
                // Get the next audio sample
                if let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                   let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    // Read data from the buffer
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var buffer = Data(count: length)
                    buffer.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    // Write the audio data to the stream
                    stream.write(buffer)
                }
            }

            if reader.status == .completed {
                print("Audio streaming completed.") // Log successful streaming
            } else {
                print("Error during audio streaming: \(String(describing: reader.error))") // Log any errors
            }

            // Close the audio stream
            stream.close()
        } catch {
            print("Error reading audio file: \(error.localizedDescription)") // Log exceptions
            updateLabels(detectedText: "Error: Audio streaming failed.", translatedText: nil)
        }
    }

    
    @objc func updateDisplayedText() {
        // Check if there is an active video player
        guard let player = videoPlayer else { return }

        // Get the current playback time in seconds
        let currentTime = CMTimeGetSeconds(player.currentTime())

        // Check which speech segment corresponds to the current playback time
        for segment in speechSegments {
            if currentTime >= segment.start && currentTime <= segment.end {
                // Update labels with detected text and translation
                updateLabels(detectedText: segment.detectedText, translatedText: segment.translatedText)
                return
            }
        }

        // If no matching segment, display default messages
        updateLabels(detectedText: "No text detected.", translatedText: "No translation available.")
    }
    
    func updateLabels(detectedText: String?, translatedText: String?) {
        // Update the UI on the main thread
        DispatchQueue.main.async {
            self.detectedTextLabel.text = detectedText ?? "No text detected." // Set detected speech
            self.translatedTextLabel.text = translatedText ?? "No translation available." // Set translation
        }
    }

}
