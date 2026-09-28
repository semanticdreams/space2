# bt

## Canonical Import

```fennel
(local bt (require :bt))
```

## Source Files

- `src/lua_physics.cpp`
- `src/physics.h`

## What It Provides

`bt` exposes the Bullet-backed physics binding used by Space for rigid bodies, collision shapes, dynamics worlds, constraints, vehicles, and runtime physics integration. `physics` is a search alias for this canonical `bt` module, not an importable module page.

## API Summary

- Math and transforms: `Scalar`, `Vector3`, `Quaternion`, and `Transform`.
- Collision shapes and meshes: `TriangleMesh`, `BvhTriangleMeshShape`, `HeightfieldTerrainShape`, `StaticPlaneShape`, `BoxShape`, `SphereShape`, and shared `CollisionShape` methods.
- Bodies and motion: `DefaultMotionState`, `RigidBodyConstructionInfo`, `RigidBody`, `CollisionObject`, and activation/collision flag constants.
- Worlds and setup: `DefaultCollisionConfiguration`, `CollisionDispatcher`, `DbvtBroadphase`, `SequentialImpulseConstraintSolver`, `DiscreteDynamicsWorld`, and `SoftRigidDynamicsWorld`.
- Constraints and vehicles: `Point2PointConstraint`, `VehicleTuning`, `DefaultVehicleRaycaster`, and `RaycastVehicle`.
- `Physics` exposes engine-owned world helpers such as `setGravity`, `addRigidBody`, `removeRigidBody`, `updateSingleAabb`, `syncMovedRigidBody`, `addAction`, `removeAction`, `addConstraint`, `removeConstraint`, `getNumConstraints`, `getWorld`, and `update`.

## Examples

```fennel
(local bt (require :bt))

(local shape (bt.BoxShape (bt.Vector3 0.5 0.5 0.5)))
(local transform (bt.Transform))
(transform:setIdentity)
(transform:setOrigin (bt.Vector3 0 5 0))
(local motion (bt.DefaultMotionState transform))
(local info (bt.RigidBodyConstructionInfo 1.0 motion shape (bt.Vector3 0 0 0)))
(local body (bt.RigidBody info))
```

## Errors and Platform Notes

Constructors validate required pointers and dimensions. For example, heightfield width/length must be greater than 1 and the heights table length must equal `width * length`; `Point2PointConstraint` requires a rigid body. Manage object lifetimes carefully because Bullet worlds and shapes may hold native pointers.

## Related Modules

- [`glm`](/sdk/modules/glm) for rendering-side math values.
- [`perlin-terrain-native`](/sdk/modules/perlin-terrain-native) for terrain meshes that can add triangles to `bt.TriangleMesh`.

## Aliases and Search Terms

Search terms: physics, Bullet, bt, rigid body, collision shape, dynamics world, constraint, vehicle, heightfield.
