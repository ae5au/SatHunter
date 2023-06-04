import Foundation


import SwiftUI
import CoreLocation
import OSLog

fileprivate let logger = Logger()

class SatViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
  var trackedSat: SatOrbitElements? = nil {
    didSet {
      self.refresh()
    }
  }
  // whether the sat is currently passing.
  // if nil, none if the data below are available.
  @Published var visible: Bool? = nil
  
  // the following only available when visible == false
  @Published var nextAos: Date? = nil
  @Published var nextLos: Date? = nil
  // in degree
  @Published var maxEl: Double? = nil
  
  // the following only available when visible == true
  @Published var currentLos: Date? = nil
  // both in degree
  @Published var currentAz: Double? = nil
  @Published var currentEl: Double? = nil
  
  @Published var userHeading: Double = 0
  @Published var userLat: Double = 0
  @Published var userLon: Double = 0
  @Published var userAlt: Double = 0
  @Published var userGridSquare: String = ""
  
  private var timer: Timer? = nil
  private var locationManager: CLLocationManager? = nil
  // APPLE PARK (:D)
  // 37.33481435508938, -122.00893980785605
  private var observer = SatObserver(name: "user", lat: 37.33481435508938, lon:-122.00893980785605, alt: 25)
  override init() {
    super.init()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: {_ in self.refresh()})
    locationManager = CLLocationManager()
    locationManager!.delegate = self
    locationManager!.requestWhenInUseAuthorization()
    if !CLLocationManager.headingAvailable() {
      logger.error("CLLocationManager: headingAvailable returned false")
    }
    locationManager!.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    locationManager!.startUpdatingLocation()
    locationManager!.startUpdatingHeading()
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    self.userHeading = newHeading.trueHeading
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let location = locations.last {
      userAlt = location.altitude
      userLon = location.coordinate.longitude
      userLat = location.coordinate.latitude
      observer = SatObserver(name: "user", lat: userLat, lon: userLon, alt: userAlt)
      userGridSquare = latLonToGridSquare(lat: userLat, lon: userLon)
    }
  }

  func refresh() {
    if let trackedSat = trackedSat {
      if case let .success(observation) = getSatObservation(observer: observer,
                                                            orbit: trackedSat)
      {
        if observation.elevation > 0 {
          currentAz = observation.azimuth.deg
          currentEl = observation.elevation.deg
          let los = getSatNextLos(observer: observer, orbit: trackedSat)
          currentLos = los.date
        } else {
          let nextPass = getNextSatPass(observer: observer, orbit: trackedSat)
          nextAos = nextPass.aos.date
          nextLos = nextPass.los.date
          maxEl = nextPass.maxElevation.elevation.deg
        }
        visible = observation.elevation > 0
      }
    }
  }
}
// az, el in degree
func azElToXy(az: Double, el: Double) -> (Double, Double) {
  var r = 1 - el / 90
  r = max(0, r)
  r = min(1, r)
  return (r * sin(az.rad), r * cos(az.rad))
}

func latLonToGridSquare(lat: Double, lon: Double) -> String {
  var lon = lon + 180
  var lat = lat + 90
  var result = ""
  var lonBand = floor(lon / 20)
  var latBand = floor(lat / 10)
  result.append(Character(UnicodeScalar((UInt8(lonBand) + Character("A").asciiValue!))))
  result.append(Character(UnicodeScalar((UInt8(latBand) + Character("A").asciiValue!))))
  lon -= lonBand * 20
  lat -= latBand * 10
  lonBand = lon / 2
  latBand = lat
  result.append(Character(UnicodeScalar((UInt8(lonBand) + Character("0").asciiValue!))))
  result.append(Character(UnicodeScalar((UInt8(latBand) + Character("0").asciiValue!))))
  return result
}

struct SatView: View {
//  @Binding var satName: String?
//  @Binding var trackedSat: SatOrbitElements?
  @Binding var trackedSat: Satellite?
  @ObservedObject var model = SatViewModel()
  
  var body: some View {
    HStack {
      GeometryReader { g in
        let width = g.size.width
        let height = g.size.height
        ZStack {
          // The background of the sky view
          Circle().stroke()
          Circle().scale(0.667).stroke()
          Circle().scale(0.333).stroke()
          Path {
            path in
            path.move(to: .init(x: width / 2, y: height / 2 - (width / 2)))
            path.addLine(to: .init(x: width / 2, y: height / 2 + (width / 2)))
          }.stroke()
          Path {
            path in
            path.move(to: .init(x: 0, y: height / 2))
            path.addLine(to: .init(x: width, y: height / 2))
          }.stroke()
          
          // Red dot in the sky view for the currently tracked sat.
          if let visible = model.visible {
            if visible {
              Path {
                path in
                let (x, y) = azElToXy(az: model.currentAz!,
                                      el: model.currentEl!)
                let r = min(width, height) / 2
                // the Y origin is top-left corner, thus the minus sign before y * r.
                let center = CGPoint(x: width / 2 + x * r, y: height / 2 - y * r)
                path.move(to: center)
                path.addArc(
                  center: center,
                  radius: 3,
                  startAngle: .init(degrees: 0),
                  endAngle: .init(degrees: 360),
                  clockwise: true
                )
              }.fill(.red)
            }
          }
          
          Path {
            path in
            path.move(to: .init(x: width / 2, y: height / 2))
            let r = min(width, height) / 2
            let heading = model.userHeading.rad
            let x = width / 2 + r * sin(heading)
            let y = height / 2 - r * cos(heading)
            path.addLine(to: .init(x: x, y: y))
          }.stroke(.blue.opacity(0.4), lineWidth: 5)
        }
      }
      
      VStack {
        if let satName = trackedSat?.name {
          Text(satName).font(.title).onAppear {
            if let tle = trackedSat?.tleTuple {
              model.trackedSat = SatOrbitElements(tle)
            }
          }
          if let visible = model.visible {
            if visible {
              Text("Passing")
              HStack {
                Text("LOS:")
                Spacer()
                Text(
                  "\(model.currentLos!.formatted(date: .omitted, time: .shortened)) (\(Duration.seconds(model.currentLos!.timeIntervalSinceNow).formatted(.time(pattern: .minuteSecond))))"
                )
              }
            } else {
              Text("Next pass")
              HStack {
                Text("AOS:")
                Spacer()
                Text(
                  "\(model.nextAos!.formatted(date: .omitted, time: .shortened))"
                )
              }
              HStack {
                Text("LOS:")
                Spacer()
                Text(
                  "\(model.nextLos!.formatted(date: .omitted, time: .shortened))"
                )
              }
              HStack {
                Text(
                  "Max el:"
                )
                Spacer()
                Text("\(String(format: "%.0f", model.maxEl!)) deg")
              }
            }
            HStack {
              Text("Your grid:")
              Spacer()
              Text(model.userGridSquare)
            }
            HStack {
              Text("Times are local").font(.footnote)
              Spacer()
            }
          } else {
            Text("Calculating...")
          }
        } else {
          Text("Select a sattelite below")
        }
      }.frame(maxWidth: .infinity).font(.body.monospaced())
    }
  }
}