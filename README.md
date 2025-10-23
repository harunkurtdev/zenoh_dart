# zenoh_dart

A Dart binding for Zenoh - a high-performance, zero-overhead pub/sub, store/query (not yet) and compute protocol that unifies data in motion,
data at rest and computations. zenoh_dart enables Dart and Flutter applications to seamlessly integrate with Zenoh's distributed systems capabilities.

![Video](./docs/video.MP4)

## Development Checklist

- [X] Basic Zenoh session management
- [X] Publisher implementation
- [X] Subscriber implementation  
- [ ] Query/Reply functionality
- [ ] Storage operations
- [ ] Error handling
- [X] Examples
- [ ] Performance optimization
- [X] Platform compatibility (Android)
- [X] Platform compatibility (Linux x86_64)
- [ ] Platform compatibility (Linux aarch64 not tested)
- [X] Platform compatibility (MacOS) (universal platform, build problem for release)
- [ ] Platform compatibility (iOS) (not tested)
- [ ] Platform compatibility (Win) ( x86_64 not tested)
- [ ] Platform compatibility (Win) ( aarch64 not tested)
- [ ] CI/CD pipeline
- [ ] Package publishing

## Features Status

- [X] Multi-platform support
- [X] Core Zenoh binding
- [X] Pub/Sub messaging
- [ ] Queryable interface
- [ ] Storage interface
- [ ] Authentication support
- [ ] TLS/Security features
  
## Testing 

### Subscription Testing

    python3 sub.py

### Publishing Testing

    python3 pub.py