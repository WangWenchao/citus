--
-- Hide shard names on MX worker nodes
--

ALTER SEQUENCE pg_catalog.pg_dist_shardid_seq RESTART 1130000;


-- make sure that the signature of the citus_table_is_visible
-- and pg_table_is_visible are the same since the logic
-- relies on that
SELECT
	proname, proisstrict, proretset, provolatile,
	proparallel, pronargs, pronargdefaults ,prorettype,
	proargtypes, proacl
FROM
	pg_proc
WHERE
	proname LIKE '%table_is_visible%'
ORDER BY 1;

CREATE SCHEMA mx_hide_shard_names;
SET search_path TO 'mx_hide_shard_names';

SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_2_port);

CREATE TABLE test_table(id int, time date);
SELECT create_distributed_table('test_table', 'id');

-- first show that the views does not show
-- any shards on the coordinator as expected
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names';
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'mx_hide_shard_names';

-- now show that we see the shards, but not the
-- indexes as there are no indexes
\c postgresql://postgres@localhost::worker_1_port/regression?application_name=psql
SET search_path TO 'mx_hide_shard_names';
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;

-- make sure that pg_class queries do not get blocked on table locks
begin;
lock table test_table in access exclusive mode;
prepare transaction 'take-aggressive-lock';

-- shards are hidden when using psql as application_name
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

commit prepared 'take-aggressive-lock';

-- now create an index
\c - - - :master_port
SET search_path TO 'mx_hide_shard_names';
CREATE INDEX test_index ON mx_hide_shard_names.test_table(id);

-- now show that we see the shards, and the
-- indexes as well
\c postgresql://postgres@localhost::worker_1_port/regression?application_name=psql
SET search_path TO 'mx_hide_shard_names';
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;

-- shards are hidden when using psql as application_name
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- changing application_name reveals the shards
SET application_name TO 'pg_regress';
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;
RESET application_name;

-- shards are hidden again after GUCs are reset
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- changing application_name in transaction reveals the shards
BEGIN;
SET LOCAL application_name TO 'pg_regress';
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;
ROLLBACK;

-- shards are hidden again after GUCs are reset
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- now with session-level GUC, but ROLLBACK;
BEGIN;
SET application_name TO 'pg_regress';
ROLLBACK;

-- shards are hidden again after GUCs are reset
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- we should hide correctly based on application_name with savepoints
BEGIN;
SAVEPOINT s1;
SET application_name TO 'pg_regress';
-- changing application_name reveals the shards
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;
ROLLBACK TO SAVEPOINT s1;
-- shards are hidden again after GUCs are reset
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;
ROLLBACK;

-- changing citus.show_shards_for_app_name_prefix reveals the shards
BEGIN;
SET LOCAL citus.show_shards_for_app_name_prefixes TO 'psql';
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;
ROLLBACK;

-- shards are hidden again after GUCs are reset
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- we should be able to select from the shards directly if we
-- know the name of the tables
SELECT count(*) FROM test_table_1130000;

-- shards on the search_path still match pg_table_is_visible
SELECT pg_table_is_visible('test_table_1130000'::regclass);

-- shards on the search_path do not match citus_table_is_visible
SELECT citus_table_is_visible('test_table_1130000'::regclass);

\c - - - :master_port
-- make sure that we're resilient to the edge cases
-- such that the table name includes the shard number
SET search_path TO 'mx_hide_shard_names';
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

-- not existing shard ids appended to the distributed table name
CREATE TABLE test_table_102008(id int, time date);
SELECT create_distributed_table('test_table_102008', 'id');

\c - - - :worker_1_port
SET search_path TO 'mx_hide_shard_names';

-- existing shard ids appended to a local table name
-- note that we cannot create a distributed or local table
-- with the same name since a table with the same
-- name already exists :)
CREATE TABLE test_table_2_1130000(id int, time date);

SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;

\d

\c - - - :master_port
-- make sure that don't mess up with schemas
CREATE SCHEMA mx_hide_shard_names_2;
SET search_path TO 'mx_hide_shard_names_2';
SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;
CREATE TABLE test_table(id int, time date);
SELECT create_distributed_table('test_table', 'id');
CREATE INDEX test_index ON mx_hide_shard_names_2.test_table(id);

\c - - - :worker_1_port
SET search_path TO 'mx_hide_shard_names';
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'mx_hide_shard_names' ORDER BY 2;
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names_2' ORDER BY 2;
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'mx_hide_shard_names_2' ORDER BY 2;

-- now try very long table names
\c - - - :master_port

SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

CREATE SCHEMA mx_hide_shard_names_3;
SET search_path TO 'mx_hide_shard_names_3';

-- Verify that a table name > 56 characters handled properly.
CREATE TABLE too_long_12345678901234567890123456789012345678901234567890 (
        col1 integer not null,
        col2 integer not null);
SELECT create_distributed_table('too_long_12345678901234567890123456789012345678901234567890', 'col1');

\c - - - :worker_1_port
SET search_path TO 'mx_hide_shard_names_3';
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'mx_hide_shard_names_3' ORDER BY 2;
\d



-- now try weird schema names
\c - - - :master_port

SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

CREATE SCHEMA "CiTuS.TeeN";
SET search_path TO "CiTuS.TeeN";

CREATE TABLE "TeeNTabLE.1!?!"(id int, "TeNANt_Id" int);

CREATE INDEX "MyTenantIndex" ON  "CiTuS.TeeN"."TeeNTabLE.1!?!"("TeNANt_Id");
-- create distributed table with weird names
SELECT create_distributed_table('"CiTuS.TeeN"."TeeNTabLE.1!?!"', 'TeNANt_Id');

\c - - - :worker_1_port
SET search_path TO "CiTuS.TeeN";
SELECT * FROM citus_shards_on_worker WHERE "Schema" = 'CiTuS.TeeN' ORDER BY 2;
SELECT * FROM citus_shard_indexes_on_worker WHERE "Schema" = 'CiTuS.TeeN' ORDER BY 2;

\d
\di


\c - - - :worker_1_port
-- re-connect to the worker node and show that only
-- client backends can filter shards
SET search_path TO "CiTuS.TeeN";

-- Create the necessary test utility function
SET citus.enable_metadata_sync TO off;
CREATE OR REPLACE FUNCTION set_backend_type(backend_type int)
    RETURNS void
    LANGUAGE C STRICT
    AS 'citus';
RESET citus.enable_metadata_sync;

-- the shards and indexes do not show up
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- say, we set it to bgworker
-- the shards and indexes do not show up
SELECT set_backend_type(4);
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- or, we set it to walsender
-- the shards and indexes do show up
SELECT set_backend_type(9);
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;

-- but, client backends to see the shards
SELECT set_backend_type(3);
SELECT relname FROM pg_catalog.pg_class WHERE relnamespace = 'mx_hide_shard_names'::regnamespace ORDER BY relname;


-- clean-up
\c - - - :master_port

-- show that common psql functions do not show shards
-- including the ones that are not in the current schema
SET search_path TO 'mx_hide_shard_names';
\d
\di

DROP SCHEMA mx_hide_shard_names CASCADE;
DROP SCHEMA mx_hide_shard_names_2 CASCADE;
DROP SCHEMA mx_hide_shard_names_3 CASCADE;
DROP SCHEMA "CiTuS.TeeN" CASCADE;
