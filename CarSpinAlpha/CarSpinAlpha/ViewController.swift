//
//  ViewController.swift
//  CarSpinAlpha
//
//  Created by Mo DeJong on 4/4/19.
//  Copyright © 2019 HelpURock. All rights reserved.
//

import UIKit
import AlphaOverVideo

class ViewController: UIViewController {

  @IBOutlet weak var mtkView: AOVMTKView!
  
  var player: AOVPlayer?

  override func viewDidLoad() {
    super.viewDidLoad()
    
    mtkView.device = MTLCreateSystemDefaultDevice()
    
    if (mtkView.device == nil)
    {
      NSLog("Metal is not supported on this device");
      return;
    }
        
    // Generate RGBA pair or urls to seamless loop an infinite number of times
    let url1 = AOVPlayer.url(fromAsset:"CarSpin.m4v")
    let url2 = AOVPlayer.url(fromAsset:"CarSpin_alpha.m4v")
    assert(url1 != nil)
    assert(url2 != nil)
    let clips = [ [ url1, url2 ] ]
    
    let player = AOVPlayer.init(loopedClips:clips)
    self.player = player
    
    let worked = mtkView.attach(player)
    if (worked == false)
    {
      NSLog("attach failed for AOVMTKView");
      return;
    }
    
    if (true) {
      // Cycle background color change animation to demonstrate alpha channel
      
      let view = self.view!;
      
      view.backgroundColor = UIColor.darkGray
      UIView.beginAnimations(nil, context: nil)
      UIView.setAnimationDuration(5.0)
      UIView.setAnimationRepeatCount(30.0)
      UIView.setAnimationRepeatAutoreverses(true)
      view.backgroundColor = UIColor.white
      UIView.commitAnimations()
    }

  }
}

