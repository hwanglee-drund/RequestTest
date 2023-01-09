//
//  DProgress.swift
//  Request
//
//  Created by Shawna MacNabb on 10/14/20.
//  Copyright © 2020 Shawna MacNabb. All rights reserved.
//

import UIKit

protocol DProgressGroupDelegate: AnyObject {
    func progressUnitUpdate(_ progress: DProgress)
}

public class ProgressGroup: NSObject, DProgressGroupDelegate {
    
    private var children: [DProgress] = [DProgress]()
    
    private(set) public var parentProgress: DProgress = DProgress(isParentProgress: true)

    override public init() { }
    
    public func addChild(progress: DProgress) {
        progress.delegate = self
        self.children.append(progress)
        
        updateParentProgress()
    }
    
    //MARK: DProgressGroupDelegate
    func progressUnitUpdate(_ progress: DProgress) {
        updateParentProgress()
    }
    
    private func updateParentProgress() {
        // update the parent
        // the parent progress is configured by calculating the fraction completed manually because of pending tasks that have no totalUnitCount/completedUnitCount
        // Since the pending progresses have no values to calculate with, we assume all have a completedUnitCount that cannot exceed 1
        
        var completedUnitCount: Int64 = 0
        var completedFractionCount: Float = 0.0
                
        for progressItem in children {
            if progressItem.completedUnitCount == progressItem.totalUnitCount {
                completedUnitCount += 1
                completedFractionCount += 1.0
            } else {
                completedFractionCount += progressItem.fractionCompleted
            }
        }
        
        parentProgress.totalUnitCount = Int64(children.count)
        let fractionCompleted = completedFractionCount / Float(children.count)
        parentProgress.setParent(fractionCompleted: fractionCompleted)
    }
}

public class DProgress: NSObject {
    
    internal weak var delegate: DProgressGroupDelegate?
    private var isParentProgress: Bool = false
    
    public var totalUnitCount: Int64 = 0 {
        didSet {
            // we don't want to configure the fractionCompeleted if the progress is the parent because that is manually done
            if !isParentProgress {
                updatePercentageCompleted()
            }
        }
    }
    
    public var completedUnitCount: Int64 = 0 {
        didSet {
            // we don't want to configure the fractionCompleted if the progress is the parent because that is manually done
            if !isParentProgress {
                updatePercentageCompleted()
            }
        }
    }
    
    @objc private(set) public dynamic var fractionCompleted: Float = 0.0
    
    private(set) var pendingUnitCount: Int64 = 0
    
    internal override init() { }
    
    internal init(isParentProgress: Bool) {
        self.isParentProgress = isParentProgress
    }
    
    public init(pendingUnitCount: Int64) {
        self.pendingUnitCount = pendingUnitCount
        self.totalUnitCount = pendingUnitCount
    }
    
    private func updatePercentageCompleted() {
        fractionCompleted = Float(completedUnitCount) / Float(totalUnitCount)
        delegate?.progressUnitUpdate(self)
    }
    
    // set the fractionCompleted manually ONLY for the parent, DO NOT USE this for any other progress, it will mess up the calculations completely, the only reason this works is because the didSet for completedUnitCount and totalUnitCount do NOT get called
    internal func setParent(fractionCompleted: Float) {
        self.fractionCompleted = fractionCompleted
    }
}
