//
//  CLibPQ.h
//  TablePro
//
//  C bridging header for libpq (PostgreSQL C API)
//  Install: brew install libpq
//

#ifndef CLibPQ_h
#define CLibPQ_h

// Use architecture-specific paths for Homebrew installations
// ARM64: /opt/homebrew (Apple Silicon)
// x86_64: /usr/local (Intel or Rosetta)
#if defined(__arm64__) || defined(__aarch64__)
    #include "/opt/homebrew/opt/libpq/include/libpq-fe.h"
#else
    #include "/usr/local/opt/libpq/include/libpq-fe.h"
#endif

#endif /* CLibPQ_h */
