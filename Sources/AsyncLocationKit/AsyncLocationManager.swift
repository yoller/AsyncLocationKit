import Foundation
import CoreLocation

public typealias AuthotizationContinuation = CheckedContinuation<CLAuthorizationStatus, Never>
public typealias LocationOnceContinuation = CheckedContinuation<LocationUpdateEvent?, Error>
public typealias LocationStream = AsyncStream<LocationUpdateEvent>
public typealias RegionMonitoringStream = AsyncStream<RegionMonitoringEvent>
public typealias VisitMonitoringStream = AsyncStream<VisitMonitoringEvent>
public typealias HeadingMonitorStream = AsyncStream<HeadingMonitorEvent>
public typealias BeaconsRangingStream = AsyncStream<BeaconRangeEvent>

public final class AsyncLocationManager {
    
    public private(set) var locationManager: CLLocationManager
    private var proxyDelegate: AsyncDelegateProxyInterface
    private var locationDelegate: CLLocationManagerDelegate
    private var desiredAccuracy: LocationAccuracy = .bestAccuracy
    
    public init() {
        locationManager = CLLocationManager()
        proxyDelegate = AsyncDelegateProxy()
        locationDelegate = LocationDelegate(delegateProxy: proxyDelegate)
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = desiredAccuracy.convertingAccuracy
    }
    
    public convenience init(desiredAccuracy: LocationAccuracy) {
        self.init()
        self.desiredAccuracy = desiredAccuracy
    }
    
    public func requestAuthorizationWhenInUse() async -> CLAuthorizationStatus {
        let authorizationPerformer = RequestAuthorizationPerformer()
        return await withTaskCancellationHandler {
            proxyDelegate.cancel(for: authorizationPerformer.uniqueIdentifier)
        } operation: {
            await withCheckedContinuation { continuation in
                authorizationPerformer.linkContinuation(continuation)
                proxyDelegate.addPerformer(authorizationPerformer)
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
    
    public func requestAuthorizationAlways() async -> CLAuthorizationStatus {
        let authorizationPerformer = RequestAuthorizationPerformer()
        return await withTaskCancellationHandler {
            proxyDelegate.cancel(for: authorizationPerformer.uniqueIdentifier)
        } operation: {
            await withCheckedContinuation { continuation in
                authorizationPerformer.linkContinuation(continuation)
                proxyDelegate.addPerformer(authorizationPerformer)
                locationManager.requestAlwaysAuthorization()
            }
        }
    }
    
    public func startUpdatingLocation() async -> LocationStream {
        let monitoringPerformer = MonitoringUpdateLocationPerformer()
        return LocationStream { streamContinuation in
            monitoringPerformer.linkContinuation(streamContinuation)
            proxyDelegate.addPerformer(monitoringPerformer)
            locationManager.startUpdatingLocation()
            streamContinuation.onTermination = { @Sendable _ in
                self.proxyDelegate.cancel(for: monitoringPerformer.uniqueIdentifier)
            }
        }
    }
    
    public func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        proxyDelegate.cancel(for: MonitoringUpdateLocationPerformer.self)
    }
    
    public func requestLocation() async throws -> LocationUpdateEvent? {
        let performer = SingleLocationUpdatePerformer()
        return try await withTaskCancellationHandler(handler: {
            proxyDelegate.cancel(for: performer.uniqueIdentifier)
        }, operation: {
            return try await withCheckedThrowingContinuation({ continuation in
                performer.linkContinuation(continuation)
                self.proxyDelegate.addPerformer(performer)
                self.locationManager.requestLocation()
            })
        })
    }
    
    public func startMonitoring(for region: CLRegion) async -> RegionMonitoringStream {
        let performer = RegionMonitoringPerformer(region: region)
        return RegionMonitoringStream { streamContinuation in
            performer.linkContinuation(streamContinuation)
            locationManager.startMonitoring(for: region)
            streamContinuation.onTermination = { @Sendable _ in
                self.proxyDelegate.cancel(for: performer.uniqueIdentifier)
            }
        }
    }
    
    public func stopMonitoring(for region: CLRegion) {
        proxyDelegate.cancel(for: RegionMonitoringPerformer.self) { regionMonitoring in
            guard let regionPerformer = regionMonitoring as? RegionMonitoringPerformer else { return false }
            return regionPerformer.region ==  region
        }
        locationManager.stopMonitoring(for: region)
    }
    
    public func startMonitoringVisit() async -> VisitMonitoringStream {
        let performer = VisitMonitoringPerformer()
        return VisitMonitoringStream { stream in
            performer.linkContinuation(stream)
            proxyDelegate.addPerformer(performer)
            locationManager.startMonitoringVisits()
            stream.onTermination = { @Sendable _ in
                self.stopMonitoringVisit()
            }
        }
    }
    
    public func stopMonitoringVisit() {
        proxyDelegate.cancel(for: VisitMonitoringPerformer.self)
        locationManager.stopMonitoringVisits()
    }
    
    public func startUpdatingHeading() async -> HeadingMonitorStream {
        let performer = HeadingMonitorPerformer()
        return HeadingMonitorStream { stream in
            performer.linkContinuation(stream)
            proxyDelegate.addPerformer(performer)
            locationManager.startUpdatingHeading()
            stream.onTermination = { @Sendable _ in
                self.stopUpdatingHeading()
            }
        }
    }
    
    public func stopUpdatingHeading() {
        proxyDelegate.cancel(for: HeadingMonitorPerformer.self)
        locationManager.stopUpdatingHeading()
    }
    
    public func startRangingBeacons(satisfying: CLBeaconIdentityConstraint) async -> BeaconsRangingStream {
        let performer = BeaconsRangePerformer(satisfying: satisfying)
        return BeaconsRangingStream { stream in
            performer.linkContinuation(stream)
            proxyDelegate.addPerformer(performer)
            locationManager.startRangingBeacons(satisfying: satisfying)
            stream.onTermination = { @Sendable _ in
                self.stopRangingBeacons(satisfying: satisfying)
            }
        }
    }
    
    public func stopRangingBeacons(satisfying: CLBeaconIdentityConstraint) {
        proxyDelegate.cancel(for: BeaconsRangePerformer.self) { beaconsMonitoring in
            guard let beaconsPerformer = beaconsMonitoring as? BeaconsRangePerformer else { return false }
            return beaconsPerformer.satisfying == satisfying
        }
        locationManager.stopRangingBeacons(satisfying: satisfying)
    }
    
}
