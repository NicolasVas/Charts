//
//  ChartHighlighter.swift
//  Charts
//
//  Copyright 2015 Daniel Cohen Gindi & Philipp Jahoda
//  A port of MPAndroidChart for iOS
//  Licensed under Apache License 2.0
//
//  https://github.com/danielgindi/Charts
//

import Foundation
import CoreGraphics

open class ChartHighlighter : NSObject, Highlighter
{
 
    /**
     This value is based on the Apple HMI recommandation : minimum 'interactive' target size of 44 x 44px
     */
    private let minimum_target_size = CGFloat(44)
    
    /**
     The minimum distance between a tap location and a trigger point
     This value is based on the Apple HMI recommandation (minimum 'interactive' target size of 44 x 44px, so a 22px radius circle around the tap point)
     */
    private let minimum_radius_size = CGFloat(22)
    
    /// instance of the data-provider
    @objc open weak var chart: ChartDataProvider?
    
    @objc public init(chart: ChartDataProvider)
    {
        self.chart = chart
    }
    
    open func getHighlight(x: CGFloat, y: CGFloat) -> Highlight?
    {
        let xVal = Double(getValsForTouch(x: x, y: y).x)
        return getHighlight(xValue: xVal, x: x, y: y)
    }
    
    /// - Parameters:
    ///   - x:
    /// - Returns: The corresponding x-pos for a given touch-position in pixels.
    @objc open func getValsForTouch(x: CGFloat, y: CGFloat) -> CGPoint
    {
        guard let chart = self.chart as? BarLineScatterCandleBubbleChartDataProvider else { return .zero }
        
        // take any transformer to determine the values
        return chart.getTransformer(forAxis: .left).valueForTouchPoint(x: x, y: y)
    }
    
    /// - Parameters:
    ///   - xValue:
    ///   - x:
    ///   - y:
    /// - Returns: The corresponding ChartHighlight for a given x-value and xy-touch position in pixels.
    @objc open func getHighlight(xValue xVal: Double, x: CGFloat, y: CGFloat) -> Highlight?
    {
        guard let chart = chart else { return nil }
        
        let closestValues = getHighlights(xValue: xVal, x: x, y: y)
        guard !closestValues.isEmpty else { return nil }
        
        let leftAxisMinDist = getMinimumDistance(closestValues: closestValues, y: y, axis: .left)
        let rightAxisMinDist = getMinimumDistance(closestValues: closestValues, y: y, axis: .right)
        
        let axis: YAxis.AxisDependency = leftAxisMinDist < rightAxisMinDist ? .left : .right
        
        let detail = closestSelectionDetailByPixel(closestValues: closestValues, x: x, y: y, axis: axis, minSelectionDistance: chart.maxHighlightDistance)
        
        return detail
    }
    
    /// - Parameters:
    ///   - xValue: the transformed x-value of the x-touch position
    ///   - x: touch position
    ///   - y: touch position
    /// - Returns: A list of Highlight objects representing the entries closest to the given xVal.
    /// The returned list contains two objects per DataSet (closest rounding up, closest rounding down).
    @objc open func getHighlights(xValue: Double, x: CGFloat, y: CGFloat) -> [Highlight]
    {
        var vals = [Highlight]()
        
        guard let data = self.data else { return vals }
        
        for (i, set) in zip(data.indices, data) where set.isHighlightEnabled
        {
            // extract all y-values from all DataSets at the given x-value.
            // some datasets (i.e bubble charts) make sense to have multiple values for an x-value. We'll have to find a way to handle that later on. It's more complicated now when x-indices are floating point.
            vals.append(contentsOf: buildHighlights(dataSet: set, dataSetIndex: i, xValue: xValue, rounding: .closest))
        }
        
        return vals
    }
    
    /// - Returns: An array of `Highlight` objects corresponding to the selected xValue and dataSetIndex.
    internal func buildHighlights(
        dataSet set: ChartDataSetProtocol,
        dataSetIndex: Int,
        xValue: Double,
        rounding: ChartDataSetRounding) -> [Highlight]
    {
        guard let chart = self.chart as? BarLineScatterCandleBubbleChartDataProvider else { return [] }
        
        var entries = set.entriesForXValue(xValue)
        if entries.isEmpty, let closest = set.entryForXValue(xValue, closestToY: .nan, rounding: rounding)
        {
            // Try to find closest x-value and take all entries for that x-value
            entries = set.entriesForXValue(closest.x)
        }

        return entries.map { e in
            let px = chart.getTransformer(forAxis: set.axisDependency)
                .pixelForValues(x: e.x, y: e.y)
            
            return Highlight(x: e.x, y: e.y, xPx: px.x, yPx: px.y, dataSetIndex: dataSetIndex, axis: set.axisDependency)
        }
    }

    // - MARK: - Utilities
    
    /// - Returns: The `ChartHighlight` of the closest value on the x-y cartesian axes
    internal func closestSelectionDetailByPixel(
        closestValues: [Highlight],
        x: CGFloat,
        y: CGFloat,
        axis: YAxis.AxisDependency?,
        minSelectionDistance: CGFloat) -> Highlight?
    {
        var distanceIsFromLineChart = false
        var distance = minSelectionDistance
        var closest: Highlight?
        var highlighterChartData : ChartData?
        
        let chartFrame = (chart as! UIView).frame
        
        // We need to known the step width to constrain the closest selection distance check on "Bar" chart data
        let stepWidth = chartFrame.size.width / CGFloat(chart!.xRange)
    
        
        for high in closestValues
        {
            highlighterChartData = nil
            
            if axis == nil || high.axis == axis
            {
                // 1. Compute the distance between the finger tap position and the chart origin coordinate
                let cDistance = getDistance(x1: x, y1: y, x2: high.xPx, y2: high.yPx)
                
                // 1bis. Some checks are based on the highlighter related chart data.
                let allData = (chart as? CombinedChartDataProvider)?.combinedData?.allData
                if allData?.indices.contains(high.dataIndex) == true {
                    highlighterChartData = allData![high.dataIndex]
                }
                
                
                // 2. depending on the chart data, there's some additional tests to pass
                switch highlighterChartData {
                case is LineChartData:
                    /*
                     We consider the chart line points have a clickable area around to.
                     Thus, the clickable area is based on a circle, with a radius based on the Apple HMI recommandation (arbitrary choice)
                     */
                    
                    // 2a. test whether it's the first distance to take into account, or if the finger tap location is not too far from the chart line
                    guard cDistance <= minimum_radius_size else { continue }
                    
                    // 2b. We replace the previous closest chart line distance only the previous one is from another chart type,
                    //     or if it's a smaller value
                    guard !distanceIsFromLineChart || cDistance < distance else { continue }
                    
                    distanceIsFromLineChart = true
                    
                default:
                    /*
                     Here are all other chart cases.
                     Current implementation is specific to the Bar Chart, without any thought to the others.
                     Thus, we consider the tap location must be "inside" the bar to be valid.
                     Moreover, the current closest distance must not be a line Chart : a line chart has a higher priority.
                     If you need to handle other cases in a different way, be free to update the code.
                     */
                    
                    // 2a. Select the closest 'high'lighter
                    // However, a 'Line Chart Data' has a higher priority than any other chart data type
                    guard cDistance < distance else { continue }
                    
                    // 2b. Get the bar bottom position
                    var barChartBottom = chartFrame.origin.y + chartFrame.size.height
                    
                    if highlighterChartData is BarChartData,
                       let chart = self.chart as? BarLineScatterCandleBubbleChartDataProvider {
                        
                        if let dataSet = highlighterChartData?.dataSets.first,
                            let bottomValue = (dataSet.entryForXValue(high.x, closestToY: .nan) as? BarChartDataEntry)?.yValues?.first
                        {
                            let px = chart.getTransformer(forAxis: dataSet.axisDependency).pixelForValues(x: high.x, y: bottomValue)
                            barChartBottom = px.y
                        }
                    }
                    
                    
                   // 2c. Check whether the tap location is inside the bar, and if the current nearest distance is not from a line chart point
                    guard x >= high.xPx - stepWidth
                            && x <= high.xPx + stepWidth
                            && y < barChartBottom
                            && !distanceIsFromLineChart else { continue }
                }
                
                
                // 4. This 'high'lighter becomes the closest one to the finger tap
                closest = high
                distance = cDistance
                
            }
        }
        
        return closest
    }
    
    /// - Returns: The minimum distance from a touch-y-value (in pixels) to the closest y-value (in pixels) that is displayed in the chart.
    internal func getMinimumDistance(
        closestValues: [Highlight],
        y: CGFloat,
        axis: YAxis.AxisDependency
    ) -> CGFloat {
        var distance = CGFloat.greatestFiniteMagnitude
        
        for high in closestValues where high.axis == axis
        {
            let tempDistance = abs(getHighlightPos(high: high) - y)
            if tempDistance < distance
            {
                distance = tempDistance
            }
        }
        
        return distance
    }
    
    internal func getHighlightPos(high: Highlight) -> CGFloat
    {
        return high.yPx
    }
    
    internal func getDistance(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> CGFloat
    {
        return hypot(x1 - x2, y1 - y2)
    }
    
    internal var data: ChartData?
    {
        return chart?.data
    }
}
