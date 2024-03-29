CREATE EXTENSION IF NOT EXISTS timescaledb;


CREATE TABLE PBTX_TRANSACTIONS
(
  event_id              BIGINT NOT NULL,
  block_num             BIGINT NOT NULL,
  block_time            TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  trx_id                VARCHAR(64),
  actor                 BIGINT NOT NULL,
  seqnum                BIGINT NOT NULL,
  transaction_type      BIGINT NOT NULL,
  raw_transaction       BYTEA NOT NULL
);

SELECT create_hypertable('PBTX_TRANSACTIONS', 'block_time');

CREATE INDEX PBTX_TRANSACTIONS_I01 ON PBTX_TRANSACTIONS (actor, block_time);
CREATE INDEX PBTX_TRANSACTIONS_I02 ON PBTX_TRANSACTIONS (actor, seqnum);
CREATE INDEX PBTX_TRANSACTIONS_I03 ON PBTX_TRANSACTIONS (event_id);


CREATE TABLE CURRENT_PERMISSION
(
  actor                 BIGINT PRIMARY KEY,
  permission            BYTEA NOT NULL,
  last_modified         TIMESTAMP WITHOUT TIME ZONE NOT NULL
);



CREATE TABLE PERMISSION_HISTORY
(
  event_id              BIGINT NOT NULL,
  block_num             BIGINT NOT NULL,
  block_time            TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  trx_id                VARCHAR(64) NOT NULL,
  is_active             BOOLEAN NOT NULL,
  actor                 BIGINT NOT NULL,
  permission            BYTEA NOT NULL
);

SELECT create_hypertable('PERMISSION_HISTORY', 'block_time');

CREATE INDEX PERMISSION_HISTORY_I01 ON PERMISSION_HISTORY (actor, block_time);
CREATE INDEX PERMISSION_HISTORY_I02 ON PERMISSION_HISTORY (event_id);

