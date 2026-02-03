//
//  PartnerTrackingView.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/3/26.
//

import SwiftUI
import RealityKit
import ARKit

/// Immersive view for tracking partner with visual marker
struct PartnerTrackingView: View {
    @Environment(VoiceSpatialManager.self) private var voiceSpatialManager
    
    @State private var rootEntity: Entity?
    @State private var partnerMarkerEntity: Entity?
    @State private var hasPlacedPartner: Bool = false
    
    // ARKit session for world tracking and scene reconstruction
    @State private var arSession = ARKitSession()
    @State private var worldTracking = WorldTrackingProvider()
    @State private var sceneReconstruction: SceneReconstructionProvider?
    
    var body: some View {
        RealityView { content in
            // Create root entity for partner tracking
            let root = Entity()
            root.name = "PartnerTrackingRoot"
            content.add(root)
            rootEntity = root
            
            // Create a visual marker for partner position (semi-transparent sphere)
            let markerMesh = MeshResource.generateSphere(radius: 0.08)
            let markerMaterial = UnlitMaterial(color: .orange.withAlphaComponent(0.6))
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
            marker.name = "PartnerMarker"
            marker.isEnabled = false
            root.addChild(marker)
            partnerMarkerEntity = marker
            
        } update: { content in
            // Pulse the marker when partner is speaking
            if let marker = partnerMarkerEntity {
                let scale: Float = voiceSpatialManager.isPartnerSpeaking ? 1.3 : 1.0
                marker.scale = SIMD3<Float>(repeating: scale)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Use the tapped entity's position if available
                    placePartnerAtEntity(value.entity, fallbackLocation: value.location3D)
                }
        )
        .gesture(
            // Also allow tapping in empty space
            SpatialTapGesture()
                .onEnded { value in
                    placePartnerAtLocation(value.location3D)
                }
        )
        .task {
            await startARSession()
        }
        .task {
            await processSceneUpdates()
        }
        .onDisappear {
            voiceSpatialManager.stopListening()
        }
    }
    
    // MARK: - ARKit Session
    
    private func startARSession() async {
        do {
            let authResult = await arSession.requestAuthorization(for: [.worldSensing])
            
            guard authResult[.worldSensing] == .allowed else {
                print("❌ PartnerTrackingView: World sensing not authorized")
                return
            }
            
            if SceneReconstructionProvider.isSupported {
                let reconstruction = SceneReconstructionProvider(modes: [.classification])
                sceneReconstruction = reconstruction
                try await arSession.run([worldTracking, reconstruction])
                print("✅ PartnerTrackingView: ARKit + SceneReconstruction started")
            } else {
                try await arSession.run([worldTracking])
                print("✅ PartnerTrackingView: ARKit started (no scene reconstruction)")
            }
            
        } catch {
            print("❌ PartnerTrackingView: Failed to start ARKit - \(error)")
        }
    }
    
    // MARK: - Scene Reconstruction Updates
    
    private func processSceneUpdates() async {
        guard let reconstruction = sceneReconstruction else { return }
        
        for await update in reconstruction.anchorUpdates {
            switch update.event {
            case .added, .updated:
                break
            case .removed:
                break
            }
        }
    }
    
    // MARK: - Partner Placement
    
    private func placePartnerAtEntity(_ entity: Entity, fallbackLocation: Point3D) {
        let worldTransform = entity.transformMatrix(relativeTo: nil)
        let entityPosition = SIMD3<Float>(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
        
        if simd_length(entityPosition) > 0.1 {
            updatePartnerPosition(entityPosition)
            print("✅ Partner placed on entity: \(entity.name)")
        } else {
            placePartnerAtLocation(fallbackLocation)
        }
    }
    
    private func placePartnerAtLocation(_ location3D: Point3D) {
        let partnerPosition = SIMD3<Float>(
            Float(location3D.x),
            Float(location3D.y),
            Float(location3D.z)
        )
        
        updatePartnerPosition(partnerPosition)
        print("✅ Partner placed at location: \(partnerPosition)")
    }
    
    private func updatePartnerPosition(_ position: SIMD3<Float>) {
        if let marker = partnerMarkerEntity {
            marker.position = position
            marker.isEnabled = true
        }
        
        voiceSpatialManager.setPartnerAnchorPosition(position)
        hasPlacedPartner = true
    }
}

#Preview(immersionStyle: .mixed) {
    PartnerTrackingView()
        .environment(VoiceSpatialManager())
}
