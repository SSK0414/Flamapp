import UIKit

class ViewController: UIViewController {
    private let bezierView = BezierView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        bezierView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bezierView)
        NSLayoutConstraint.activate([
            bezierView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bezierView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bezierView.topAnchor.constraint(equalTo: view.topAnchor),
            bezierView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Let the view manage motion availability internally
        // (it checks motion.isDeviceMotionAvailable)
        bezierView.attachDeviceMotion()
    }
}
