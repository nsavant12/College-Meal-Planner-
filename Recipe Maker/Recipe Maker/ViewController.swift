//
//  ViewController.swift
//  Recipe Maker
//
//  Created by Nikhil Savant on 6/22/24.
//

import AVFoundation
import UIKit
import CoreML
import Vision
import Photos

// setting up states for popup menu
private enum State {
    case closed
    case open
}

extension State {
    var opposite: State {
        switch self {
        case .open: return .closed
        case .closed: return .open
        }
    }
}


class ViewController: UIViewController {
    
    //Cam session
    var session: AVCaptureSession?
    //Photo output
    let output = AVCapturePhotoOutput()
    //Video Preview
    let previewLayer = AVCaptureVideoPreviewLayer()
    //List of ingredients to be displayed
    var ingredients: [String] = []
    

    //Shutter Button
    private let shutterButton: UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y:0, width: 100, height: 100))
        button.layer.cornerRadius = 50
        button.layer.borderWidth = 10
        button.layer.borderColor = UIColor.white.cgColor
        return button
    }()
    
    private let ingredLabel: UILabel = {
       let ingredLabel = UILabel()
        ingredLabel.text = ""
        ingredLabel.textAlignment = .center
        ingredLabel.numberOfLines = 0
        ingredLabel.textColor = UIColor.black
        return ingredLabel
    }()
    
    private let popupLabel: UILabel = {
       let popupLabel = UILabel()
        popupLabel.text = "Recipes"
        popupLabel.textAlignment = .center
        popupLabel.numberOfLines = 0
        popupLabel.textColor = UIColor.black
        return popupLabel
    }()
    
    private lazy var popupView: UIView = {
       let view = UIView()
        view.backgroundColor = .white
        view.addSubview(popupLabel)
        view.addSubview(ingredLabel)
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        view.addSubview(shutterButton)
        checkCameraPermissions()
        
        shutterButton.addTarget(self, action: #selector(didTapTakePhoto), for: .touchUpInside)
    }
    
    private var bottomConstraint = NSLayoutConstraint()
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        
        shutterButton.center = CGPoint(x: view.frame.size.width/2,
                                       y: view.frame.size.height - 125)
        ingredLabel.frame = CGRect(x: 20, y: view.frame.size.height/3,
                             width: view.frame.size.width-40, height: 100)
        popupLabel.frame = CGRect(x: 20, y: view.frame.size.height/15,
                                 width: view.frame.size.width-40, height: 100)
    }
        
    private func layout() {
        popupView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(popupView)
        popupView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        popupView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bottomConstraint = popupView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 440)
        bottomConstraint.isActive = true
        popupView.heightAnchor.constraint(equalToConstant: 500).isActive = true
    }
    
    private var currentState: State = .closed
    
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer()
        recognizer.addTarget(self, action: #selector(popupViewTapped(recognizer:)))
        return recognizer
    }()
    
    
    
    @objc private func popupViewTapped(recognizer: UITapGestureRecognizer) {
        let state = currentState.opposite
        let transitionAnimator = UIViewPropertyAnimator(duration: 1, dampingRatio: 1, animations: {
            switch state {
            case .open:
                self.bottomConstraint.constant = 0
                self.popupView.layer.cornerRadius = 20
            case .closed:
                self.bottomConstraint.constant = 440
                self.popupView.layer.cornerRadius = 0
            }
            self.view.layoutIfNeeded()
        })
        transitionAnimator.addCompletion{ position in
            switch position {
            case .start:
                self.currentState = state.opposite
            case .end:
                self.currentState = state
            default:
                ()
            }
            switch self.currentState {
            case .open:
                self.bottomConstraint.constant = 0
            case .closed:
                self.bottomConstraint.constant = 440
            }
            
        }
        transitionAnimator.startAnimation()
    }
    
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            //Req permissions
            AVCaptureDevice.requestAccess(for: .video){ [weak self] granted in
                guard granted else{
                    return
                }
                DispatchQueue.main.async {
                    self?.setUpCamera()
                }
            }
        case .restricted:
            break
        case .denied:
            break
        case .authorized:
            setUpCamera()
        @unknown default:
            break
        }
    }
    
    private func setUpCamera() {
        let session = AVCaptureSession()
        if let device = AVCaptureDevice.default(for: .video) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input){
                    session.addInput(input)
                }
                
                if session.canAddOutput(output){
                    session.addOutput(output)
                }
                
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.session = session
                
                session.startRunning()
                self.session = session
            }
            catch {
                print(error)
            }
        }
    }
    
    @objc private func didTapTakePhoto() {
        output.capturePhoto(with: AVCapturePhotoSettings(),
                            delegate: self)
    }
    
    private func analyzeImage(image: UIImage?) {
        guard let buffer = image?.resize(size: CGSize(width: 224, height: 224))?
                .getCVPixelBuffer() else{
            return
        }
        
        do {
            let config = MLModelConfiguration()
            let model = try IngredientClassifier(configuration: config)
            let modelInput = IngredientClassifierInput(image: buffer)
            
            let modelOutput = try model.prediction(input: modelInput)
            let text = modelOutput.target
            ingredients.append(text)
            ingredLabel.text = "\(ingredients)"
        }
        catch {
            print(error.localizedDescription)
        }
    }


}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else{
            return
        }
        let image = UIImage(data: data)
        
        layout()
        popupView.addGestureRecognizer(tapRecognizer)
        analyzeImage(image: image)
    }
    
    
}
