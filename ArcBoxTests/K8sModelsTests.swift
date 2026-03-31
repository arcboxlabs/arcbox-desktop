import XCTest
@testable import K8sClient

final class K8sModelsTests: XCTestCase {

    // MARK: - Pod Decoding

    func testDecodePodList() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "12345"},
            "items": [
                {
                    "metadata": {
                        "name": "nginx-abc123",
                        "namespace": "default",
                        "uid": "uid-001",
                        "creationTimestamp": "2026-01-15T10:30:00Z"
                    },
                    "spec": {
                        "containers": [
                            {"name": "nginx", "image": "nginx:latest"}
                        ]
                    },
                    "status": {
                        "phase": "Running",
                        "podIP": "10.0.0.5",
                        "containerStatuses": [
                            {"name": "nginx", "ready": true, "restartCount": 0, "image": "nginx:latest"}
                        ]
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        XCTAssertEqual(podList.metadata?.resourceVersion, "12345")
        XCTAssertEqual(podList.items.count, 1)

        let pod = podList.items[0]
        XCTAssertEqual(pod.metadata?.name, "nginx-abc123")
        XCTAssertEqual(pod.metadata?.namespace, "default")
        XCTAssertEqual(pod.metadata?.uid, "uid-001")
        XCTAssertNotNil(pod.metadata?.creationTimestamp)
        XCTAssertEqual(pod.spec?.containers?.count, 1)
        XCTAssertEqual(pod.spec?.containers?.first?.name, "nginx")
        XCTAssertEqual(pod.spec?.containers?.first?.image, "nginx:latest")
        XCTAssertEqual(pod.status?.phase, "Running")
        XCTAssertEqual(pod.status?.podIP, "10.0.0.5")
        XCTAssertEqual(pod.status?.containerStatuses?.first?.ready, true)
        XCTAssertEqual(pod.status?.containerStatuses?.first?.restartCount, 0)
    }

    func testDecodePodListEmpty() throws {
        let json = """
        {"metadata": {"resourceVersion": "1"}, "items": []}
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        XCTAssertTrue(podList.items.isEmpty)
    }

    func testDecodePodMinimalMetadata() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{"metadata": {"name": "test"}}]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        XCTAssertEqual(podList.items.first?.metadata?.name, "test")
        XCTAssertNil(podList.items.first?.spec)
        XCTAssertNil(podList.items.first?.status)
    }

    // MARK: - Service Decoding

    func testDecodeServiceList() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "67890"},
            "items": [
                {
                    "metadata": {
                        "name": "my-service",
                        "namespace": "default",
                        "uid": "svc-001"
                    },
                    "spec": {
                        "type": "ClusterIP",
                        "clusterIP": "10.96.0.1",
                        "ports": [
                            {"name": "http", "port": 80, "targetPort": 8080, "protocol": "TCP"}
                        ]
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let serviceList = try JSONDecoder.kubernetes.decode(ServiceList.self, from: json)
        XCTAssertEqual(serviceList.metadata?.resourceVersion, "67890")
        XCTAssertEqual(serviceList.items.count, 1)

        let svc = serviceList.items[0]
        XCTAssertEqual(svc.metadata?.name, "my-service")
        XCTAssertEqual(svc.metadata?.namespace, "default")
        XCTAssertEqual(svc.spec?.type, "ClusterIP")
        XCTAssertEqual(svc.spec?.clusterIP, "10.96.0.1")
        XCTAssertEqual(svc.spec?.ports?.first?.port, 80)
        XCTAssertEqual(svc.spec?.ports?.first?.name, "http")

        if case .int(let tp) = svc.spec?.ports?.first?.targetPort {
            XCTAssertEqual(tp, 8080)
        } else {
            XCTFail("Expected int targetPort")
        }
    }

    // MARK: - TargetPort

    func testDecodeTargetPortInt() throws {
        let json = """
        {"name": "http", "port": 80, "targetPort": 8080, "protocol": "TCP"}
        """.data(using: .utf8)!

        let port = try JSONDecoder().decode(ServicePort.self, from: json)
        if case .int(let tp) = port.targetPort {
            XCTAssertEqual(tp, 8080)
        } else {
            XCTFail("Expected int targetPort")
        }
    }

    func testDecodeTargetPortString() throws {
        let json = """
        {"name": "http", "port": 80, "targetPort": "http-web", "protocol": "TCP"}
        """.data(using: .utf8)!

        let port = try JSONDecoder().decode(ServicePort.self, from: json)
        if case .string(let tp) = port.targetPort {
            XCTAssertEqual(tp, "http-web")
        } else {
            XCTFail("Expected string targetPort")
        }
    }

    func testDecodeTargetPortAbsent() throws {
        let json = """
        {"name": "http", "port": 80, "protocol": "TCP"}
        """.data(using: .utf8)!

        let port = try JSONDecoder().decode(ServicePort.self, from: json)
        XCTAssertNil(port.targetPort)
    }

    // MARK: - Date Handling

    func testDecodeDateWithFractionalSeconds() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {
                    "name": "test",
                    "creationTimestamp": "2026-01-15T10:30:00.123456789Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        XCTAssertNotNil(podList.items.first?.metadata?.creationTimestamp)
    }

    func testDecodeDateWithoutFractionalSeconds() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {
                    "name": "test",
                    "creationTimestamp": "2026-01-15T10:30:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        XCTAssertNotNil(podList.items.first?.metadata?.creationTimestamp)
    }

    // MARK: - Container State

    func testDecodeContainerStateRunning() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {"name": "test"},
                "status": {
                    "phase": "Running",
                    "containerStatuses": [{
                        "name": "app",
                        "ready": true,
                        "restartCount": 2,
                        "image": "app:v1",
                        "state": {
                            "running": {"startedAt": "2026-01-15T10:30:00Z"}
                        }
                    }]
                }
            }]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        let status = podList.items.first?.status?.containerStatuses?.first
        XCTAssertNotNil(status?.state?.running)
        XCTAssertNotNil(status?.state?.running?.startedAt)
        XCTAssertNil(status?.state?.waiting)
        XCTAssertNil(status?.state?.terminated)
    }

    func testDecodeContainerStateWaiting() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {"name": "test"},
                "status": {
                    "containerStatuses": [{
                        "name": "app",
                        "ready": false,
                        "restartCount": 0,
                        "image": "app:v1",
                        "state": {
                            "waiting": {"reason": "CrashLoopBackOff"}
                        }
                    }]
                }
            }]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        let state = podList.items.first?.status?.containerStatuses?.first?.state
        XCTAssertNil(state?.running)
        XCTAssertEqual(state?.waiting?.reason, "CrashLoopBackOff")
    }

    func testDecodeContainerStateTerminated() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {"name": "test"},
                "status": {
                    "containerStatuses": [{
                        "name": "app",
                        "ready": false,
                        "restartCount": 1,
                        "image": "app:v1",
                        "state": {
                            "terminated": {"exitCode": 137, "reason": "OOMKilled"}
                        }
                    }]
                }
            }]
        }
        """.data(using: .utf8)!

        let podList = try JSONDecoder.kubernetes.decode(PodList.self, from: json)
        let state = podList.items.first?.status?.containerStatuses?.first?.state
        XCTAssertNil(state?.running)
        XCTAssertEqual(state?.terminated?.exitCode, 137)
        XCTAssertEqual(state?.terminated?.reason, "OOMKilled")
    }

    // MARK: - Service with selector

    func testDecodeServiceWithSelector() throws {
        let json = """
        {
            "metadata": {"resourceVersion": "1"},
            "items": [{
                "metadata": {"name": "svc"},
                "spec": {
                    "type": "NodePort",
                    "clusterIP": "10.96.0.1",
                    "selector": {"app": "web", "tier": "frontend"},
                    "ports": [{"port": 80, "nodePort": 30080, "protocol": "TCP"}]
                }
            }]
        }
        """.data(using: .utf8)!

        let serviceList = try JSONDecoder.kubernetes.decode(ServiceList.self, from: json)
        let svc = serviceList.items.first
        XCTAssertEqual(svc?.spec?.type, "NodePort")
        XCTAssertEqual(svc?.spec?.selector?["app"], "web")
        XCTAssertEqual(svc?.spec?.selector?["tier"], "frontend")
        XCTAssertEqual(svc?.spec?.ports?.first?.nodePort, 30080)
    }
}
