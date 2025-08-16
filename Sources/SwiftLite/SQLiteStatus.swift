public enum SQLiteStatus: Int32, CustomStringConvertible, Sendable
{
    case unknown = -1
    case ok = 0
    case error = 1
    case `internal` = 2
    case permission = 3
    case abort = 4
    case busy = 5
    case locked = 6
    case noMem = 7
    case readOnly = 8
    case interrupt = 9
    case ioErr = 10
    case corrupt = 11
    case notFound = 12
    case full = 13
    case cantOpen = 14
    case `protocol` = 15
    case schema = 17
    case tooBig = 18
    case constraint = 19
    case mismatch = 20
    case misuse = 21
    case noLFS = 22
    case auth = 23
    case range = 25
    case notADatabase = 26
    case notice = 27
    case warning = 28
    case row = 100
    case done = 101
    case okLoadPermanently = 256
    case errorMissingCollSeq = 257
    case busyRecovery = 261
    case lockedSharedCache = 262
    case readOnlyRecovery = 264
    case ioErrRead = 266
    case corruptVirtualTable = 267
    case constraintCheck = 275
    case authUser = 279
    case noticeRecoverWAL = 283
    case warningAutoindex = 284
    case abortRollback = 516
    case busySnapshot = 517
    case lockedVirtualTable = 518
    case readOnlyCantLock = 520
    case ioErrShortRead = 522
    case corruptSequence = 523
    case cantOpenIsDir = 526
    case constraintCommitHook = 531
    case noticeRecoverRollback = 539
    case errorSnapshot = 769
    case busyTimeout = 773
    case readOnlyRollback = 776
    case ioErrWrite = 778
    case corruptIndex = 779
    case cantOpenFullpath = 782
    case constraintForeignKey = 787
    case readOnlyDatabaseMoved = 1032
    case ioErrFsync = 1034
    case cantOpenConvPath = 1038
    case readOnlyCantInit = 1288
    case ioErrDirFsync = 1290
    case constraintNotNull = 1299
    case readOnlyDirectory = 1544
    case ioErrTruncate = 1546
    case cantOpenSymlink = 1550
    case constraintPrimarykey = 1555
    case ioErrFstat = 1802
    case constraintTrigger = 1811
    case ioErrUnlock = 2058
    case constraintUnique = 2067
    case ioErrReadLock = 2314
    case ioErrDelete = 2570
    case constraintRowid = 2579
    case constraintPinned = 2835
    case ioErrNoMem = 3082
    case constraintDatatype = 3091
    case ioErrAccess = 3338
    case ioErrCheckReservedLock = 3594
    case ioErrLock = 3850
    case ioErrClose = 4106
    case ioErrShmOpen = 4618
    case ioErrShmSize = 4874
    case ioErrShmMap = 5386
    case ioErrSeek = 5642
    case ioErrDeleteNoEnt = 5898
    case ioErrMmap = 6154
    case ioErrGetTempPath = 6410
    case ioErrConvPath = 6666
    case ioErrBeginAtomic = 7434
    case ioErrCommitAtomic = 7690
    case ioErrRollbackAtomic = 7946
    case ioErrData = 8202
    case ioErrCorruptFilesystem = 8458
    
    public init(_ rawValue: Int32)
    {
        if let knownStatus = Self(rawValue: rawValue) {
            self = knownStatus
        } else {
            self = .unknown
        }
    }

    public var description: String
    {
        return switch self {
        case .unknown: "SwiftLite encountered an unknown/unhandled SQLite status code."
        case .ok: "The operation was successful."
        case .error: "SQLITE_ERROR: A generic error occured."
        case .`internal`: "SQLITE_INTERNAL: An internal malfunction occured."
        case .permission: "SQLITE_PERM: Requested access mode for a newly created database could not be provided."
        case .abort: "SQLITE_ABORT: The operation was aborted prior to completion."
        case .busy: "SQLITE_BUSY: The database file could not be written or read because of concurrent activity by some other database connection."
        case .locked: "SQLITE_LOCKED: The write operation could not continue because of a conflict within the same database connection or a conflict with a different database connection that uses a shared cache."
        case .noMem: "SQLITE_NOMEM: Unable to allocate all the memory needed to complete the operation."
        case .readOnly: "SQLITE_READONLY: The current database connection does not have write permission to alter this data."
        case .interrupt: "SQLITE_INTERRUPT: The operation was interrupted."
        case .ioErr: "SQLITE_IOERR: The operation could not finish because the operating system reported an I/O error."
        case .corrupt: "SQLITE_CORRUPT: The database file has been corrupted."
        case .notFound: "SQLITE_NOTFOUND: Something was not found in the database."
        case .full: "SQLITE_FULL: The write could not complete because the disk is full."
        case .cantOpen: "SQLITE_CANTOPEN: Unable to open the specified file."
        case .`protocol`: "SQLITE_PROTOCOL: A problem with the file locking protocol used by SQLite was detected."
        case .schema: "SQLITE_SCHEMA: The database schema has changed unexpectedly."
        case .tooBig: "SQLITE_TOOBIG: The string or BLOB is too large. The default maximum length of a string or BLOB in SQLite is 1,000,000,000 bytes (~1GB)."
        case .constraint: "SQLITE_CONSTRAINT: SQL constraint violation occurred while trying to process an SQL statement."
        case .mismatch: "SQLITE_MISMATCH: Datatype mismatch detected."
        case .misuse: "SQLITE_MISUSE: The SQLite interface was used in an undefined or unsupported way. Please notify the developer."
        case .noLFS: "SQLITE_NOLFS: The database has grown to be larger than what the filesystem on this system can handle."
        case .auth: "SQLITE_AUTH: The SQL statement being prepared is not authorized."
        case .range: "SQLITE_RANGE: The parameter number argument to one of the sqlite3_bind routines or the column number in one of the sqlite3_column routines is out of range."
        case .notADatabase: "SQLITE_NOTADB: The file being opened does not appear to be an SQLite database file."
        case .notice: "SQLITE_NOTICE: An unusual operation is taking place."
        case .warning: "SQLITE_WARNING: An unusual and possibly ill-advised operation is taking place."
        case .row: "SQLITE_ROW: Another row of output is available."
        case .done: "SQLITE_DONE: The operation has completed."
        case .okLoadPermanently: "SQLITE_OK_LOAD_PERMANENTLY: The extension remains loaded into the process address space after the database connection closes."
        case .errorMissingCollSeq: "SQLITE_ERROR_MISSING_COLLSEQ: The SQL statement could not be prepared because a collating sequence named in that SQL statement could not be located."
        case .busyRecovery: "SQLITE_BUSY_RECOVERY: The operation could not continue because another process is busy recovering a WAL mode database file following a crash."
        case .lockedSharedCache: "SQLITE_LOCKED_SHAREDCACHE: Access to an SQLite data record is blocked by another database connection that is using the same record in shared cache mode."
        case .readOnlyRecovery: "SQLITE_READONLY_RECOVERY: The WAL mode database cannot be opened because the database file needs to be recovered and recovery requires write access but only read access is available."
        case .ioErrRead: "SQLITE_IOERR_READ: An I/O error in the VFS layer occurred while trying to read from a file on disk. This error might result from a hardware malfunction or because a filesystem became unmounted while the file was open."
        case .corruptVirtualTable: "SQLITE_CORRUPT_VTAB: Content in the virtual table is corrupt."
        case .constraintCheck: "SQLITE_CONSTRAINT_CHECK: A CHECK constraint failed."
        case .authUser: "SQLITE_AUTH_USER: An operation was attempted on a database for which the logged in user lacks sufficient authorization."
        case .noticeRecoverWAL: "SQLITE_NOTICE_RECOVER_WAL: The WAL mode database file is recovered."
        case .warningAutoindex: "SQLITE_WARNING_AUTOINDEX: Automatic indexing is used. This can serve as a warning to application designers that the database might benefit from additional indexes."
        case .abortRollback: "SQLITE_ABORT_ROLLBACK: An SQL statement aborted because the transaction that was active when the SQL statement first started was rolled back."
        case .busySnapshot: "SQLITE_BUSY_SNAPSHOT: The database connection tried to promote a read transaction into a write transaction but found that another database connection has already written to the database and thus invalidated prior reads."
        case .lockedVirtualTable: "SQLITE_LOCKED_VTAB: An attempt was made to update the R-Tree while another prepared statement was actively reading the R-Tree."
        case .readOnlyCantLock: "SQLITE_READONLY_CANTLOCK: Unable to obtain a read lock on a WAL mode database because the shared-memory file associated with that database is read-only."
        case .ioErrShortRead: "SQLITE_IOERR_SHORT_READ: The read attempt in the VFS layer was unable to obtain as many bytes as was requested. This might be due to a truncated file."
        case .corruptSequence: "SQLITE_CORRUPT_SEQUENCE: The schema of the sqlite_sequence table is corrupt."
        case .cantOpenIsDir: "SQLITE_CANTOPEN_ISDIR: The file open operation failed because the file is really a directory."
        case .constraintCommitHook: "SQLITE_CONSTRAINT_COMMITHOOK: A commit hook callback returned non-zero that thus caused the SQL statement to be rolled back."
        case .noticeRecoverRollback: "SQLITE_NOTICE_RECOVER_ROLLBACK: A hot journal is rolled back."
        case .errorSnapshot: "SQLITE_ERROR_SNAPSHOT: Attempted to start a read transaction on a historical version of the database, but the historical snapshot is no longer available."
        case .busyTimeout: "SQLITE_BUSY_TIMEOUT: A blocking Posix advisory file lock request in the VFS layer failed due to a timeout."
        case .readOnlyRollback: "SQLITE_READONLY_ROLLBACK: The database cannot be opened because it has a hot journal that needs to be rolled back but cannot because the database is readOnly."
        case .ioErrWrite: "SQLITE_IOERR_WRITE: An I/O error occured in the VFS layer while trying to write into a file on disk. This error might result from a hardware malfunction or because a filesystem became unmounted while the file was open."
        case .corruptIndex: "SQLITE_CORRUPT_INDEX: SQLite detected an entry is or was missing from an index."
        case .cantOpenFullpath: "SQLITE_CANTOPEN_FULLPATH: A file open operation failed because the operating system was unable to convert the filename into a full pathname."
        case .constraintForeignKey: "SQLITE_CONSTRAINT_FOREIGNKEY: The SQLITE_CONSTRAINT_FOREIGNKEY error code is an extended error code for SQLITE_CONSTRAINT indicating that a foreign key constraint failed."
        case .readOnlyDatabaseMoved: "SQLITE_READONLY_DBMOVED: The database cannot be modified because the database file has been moved since it was opened, and so any attempt to modify the database might result in database corruption if the processes crashes because the rollback journal would not be correctly named."
        case .ioErrFsync: "SQLITE_IOERR_FSYNC: An I/O error occured in the VFS layer while trying to flush previously written content out of OS and/or disk-control buffers and into persistent storage."
        case .cantOpenConvPath: "SQLITE_CANTOPEN_CONVPATH: The cygwin_conv_path() system call failed while trying to open a file."
        case .readOnlyCantInit: "SQLITE_READONLY_CANTINIT: The shared memory region used by WAL mode exists buts its content is unreliable and unusable by the current process since the current process does not have write permission on the shared memory region."
        case .ioErrDirFsync: "SQLITE_IOERR_DIR_FSYNC: An I/O error occured in the VFS layer while trying to invoke fsync() on a directory."
        case .constraintNotNull: "SQLITE_CONSTRAINT_NOTNULL: A NOT NULL constraint failed."
        case .readOnlyDirectory: "SQLITE_READONLY_DIRECTORY: The database is read-only because process does not have permission to create a journal file in the same directory as the database and the creation of a journal file is a prerequisite for writing."
        case .ioErrTruncate: "SQLITE_IOERR_TRUNCATE: An I/O error occurred in the VFS layer while trying to truncate a file to a smaller size."
        case .cantOpenSymlink: "SQLITE_CANTOPEN_SYMLINK: The SQLITE_OPEN_NOFOLLOW flag was used but the database file is a symbolic link."
        case .constraintPrimarykey: "SQLITE_CONSTRAINT_PRIMARYKEY: A PRIMARY KEY constraint failed."
        case .ioErrFstat: "SQLITE_IOERR_FSTAT: An I/O error occurred in the VFS layer while trying to invoke fstat() (or the equivalent) on a file in order to determine information such as the file size or access permissions."
        case .constraintTrigger: "SQLITE_CONSTRAINT_TRIGGER: A RAISE function within a trigger fired, causing the SQL statement to abort."
        case .ioErrUnlock: "SQLITE_IOERR_UNLOCK: An I/O error occurred within the xUnlock method on the sqlite3_io_methods object."
        case .constraintUnique: "SQLITE_CONSTRAINT_UNIQUE: A UNIQUE constraint failed."
        case .ioErrReadLock: "SQLITE_IOERR_RDLOCK: An I/O error occurred within the xLock method on the sqlite3_io_methods object while trying to obtain a read lock."
        case .ioErrDelete: "SQLITE_IOERR_DELETE: The SQLITE_IOERR_DELETE error code is an extended error code for SQLITE_IOERR indicating an I/O error within the xDelete method on the sqlite3_vfs object."
        case .constraintRowid: "SQLITE_CONSTRAINT_ROWID: The rowid is not unique."
        case .constraintPinned: "SQLITE_CONSTRAINT_PINNED: An UPDATE trigger attempted to delete the row that was being updated in the middle of the update."
        case .ioErrNoMem: "SQLITE_IOERR_NOMEM: An operation could not be completed due to the inability to allocate sufficient memory."
        case .constraintDatatype: "SQLITE_CONSTRAINT_DATATYPE: An insert or update attempted to store a value inconsistent with the column's declared type in a table defined as STRICT."
        case .ioErrAccess: "SQLITE_IOERR_ACCESS: An I/O error occured within the xAccess method on the sqlite3_vfs object."
        case .ioErrCheckReservedLock: "SQLITE_IOERR_CHECKRESERVEDLOCK: An I/O error occured within the xCheckReservedLock method on the sqlite3_io_methods object."
        case .ioErrLock: "SQLITE_IOERR_LOCK: An I/O error occurred in the advisory file locking logic."
        case .ioErrClose: "SQLITE_IOERR_CLOSE: An I/O error occurred within the xClose method on the sqlite3_io_methods object."
        case .ioErrShmOpen: "SQLITE_IOERR_SHMOPEN: An I/O error occurred within the xShmMap method on the sqlite3_io_methods object while trying to open a new shared memory segment."
        case .ioErrShmSize: "SQLITE_IOERR_SHMSIZE: An I/O error occured within the xShmMap method on the sqlite3_io_methods object while trying to enlarge a `shm` file as part of WAL mode transaction processing. This error may indicate that the underlying filesystem volume is out of space."
        case .ioErrShmMap: "SQLITE_IOERR_SHMMAP: An I/O occurred error within the xShmMap method on the sqlite3_io_methods object while trying to map a shared memory segment into the process address space."
        case .ioErrSeek: "SQLITE_IOERR_SEEK: An I/O occured error within the xRead or xWrite methods on the sqlite3_io_methods object while trying to seek a file descriptor to the beginning point of the file where the read or write is to occur."
        case .ioErrDeleteNoEnt: "SQLITE_IOERR_DELETE_NOENT: The xDelete method on the sqlite3_vfs object failed because the file being deleted does not exist."
        case .ioErrMmap: "SQLITE_IOERR_MMAP: An I/O error occurred within the xFetch or xUnfetch methods on the sqlite3_io_methods object while trying to map or unmap part of the database file into the process address space."
        case .ioErrGetTempPath: "SQLITE_IOERR_GETTEMPPATH: The VFS is unable to determine a suitable directory in which to place temporary files."
        case .ioErrConvPath: "SQLITE_IOERR_CONVPATH: The cygwin_conv_path() system call failed."
        case .ioErrBeginAtomic: "SQLITE_IOERR_BEGIN_ATOMIC: The underlying operating system reported an error on the SQLITE_FCNTL_BEGIN_ATOMIC_WRITE file-control."
        case .ioErrCommitAtomic: "SQLITE_IOERR_COMMIT_ATOMIC: The underlying operating system reported an error on the SQLITE_FCNTL_COMMIT_ATOMIC_WRITE file-control."
        case .ioErrRollbackAtomic: "SQLITE_IOERR_ROLLBACK_ATOMIC: The underlying operating system reported an error on the SQLITE_FCNTL_ROLLBACK_ATOMIC_WRITE file-control."
        case .ioErrData: "SQLITE_IOERR_DATA: The checksum on a page of the database file is incorrect."
        case .ioErrCorruptFilesystem: "SQLITE_IOERR_CORRUPTFS: A seek or read failure was due to the request not falling within the file's boundary rather than an ordinary device failure. This often indicates a corrupt filesystem."
        }
    }
}


// MARK: - Comparision with `Int`

func == (lhs: Int32, rhs: SQLiteStatus) -> Bool {
    return lhs == rhs.rawValue
}

func == (lhs: SQLiteStatus, rhs: Int32) -> Bool {
    return lhs.rawValue == rhs
}
