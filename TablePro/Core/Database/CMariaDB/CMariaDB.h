//
//  CMariaDB.h
//  TablePro
//
//  C bridging header for libmariadb (MariaDB Connector/C)
//  Install: brew install mariadb-connector-c
//

#ifndef CMariaDB_h
#define CMariaDB_h

// Use architecture-specific paths for Homebrew installations
// ARM64: /opt/homebrew (Apple Silicon)
// x86_64: /usr/local (Intel or Rosetta)
#if defined(__arm64__) || defined(__aarch64__)
    #include "/opt/homebrew/opt/mariadb-connector-c/include/mariadb/mysql.h"
#else
    #include "/usr/local/opt/mariadb-connector-c/include/mariadb/mysql.h"
#endif

#endif /* CMariaDB_h */
