ALTER TABLE pg_catalog.pg_dist_local_group ADD COLUMN logical_clock_value BIGINT NOT NULL DEFAULT 0;
UPDATE pg_catalog.pg_dist_local_group SET logical_clock_value = extract(epoch from now()) * 1000;
DROP FUNCTION IF EXISTS pg_catalog.get_cluster_clock();
CREATE OR REPLACE FUNCTION pg_catalog.get_cluster_clock()
  RETURNS BIGINT
  LANGUAGE C STABLE PARALLEL SAFE STRICT
  AS 'MODULE_PATHNAME', $$get_cluster_clock$$;
COMMENT ON FUNCTION pg_catalog.get_cluster_clock()
     IS 'returns monotonically increasing logical clock value as close to epoch value (in milli seconds) possible, with the guarantee that it will never go back from its current value even after restart and crashes';
