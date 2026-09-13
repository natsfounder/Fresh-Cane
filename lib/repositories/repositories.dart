/// Repositories interacting with Supabase RPCs and Realtime streams.
///
/// Direct client DML is revoked in the database; all writes execute
/// via the 19 transactional PostgreSQL RPCs.
library;
