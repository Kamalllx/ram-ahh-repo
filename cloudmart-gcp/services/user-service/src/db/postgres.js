'use strict';

const { Pool } = require('pg');

// Cloud SQL (PostgreSQL) via Unix socket when running on GCP
// Falls back to TCP for local development
const isGCP = process.env.DB_CONNECTION_NAME && !process.env.DB_HOST;

const pool = new Pool(
  isGCP
    ? {
        user:     process.env.DB_USER,
        password: process.env.DB_PASS,
        database: process.env.DB_NAME,
        host:     `/cloudsql/${process.env.DB_CONNECTION_NAME}`,
        max:      10,
      }
    : {
        user:     process.env.DB_USER     || 'cloudmart_admin',
        password: process.env.DB_PASS     || 'dev_password',
        database: process.env.DB_NAME     || 'cloudmart',
        host:     process.env.DB_HOST     || 'localhost',
        port:     parseInt(process.env.DB_PORT || '5432'),
        max:      10,
      },
);

pool.on('error', (err) => {
  console.error(JSON.stringify({ severity: 'ERROR', message: 'PostgreSQL pool error', error: err.message }));
});

// Create users table on startup
async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email         VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      full_name     VARCHAR(255) NOT NULL,
      role          VARCHAR(50)  NOT NULL DEFAULT 'customer',
      phone         VARCHAR(50),
      address       JSONB,
      is_active     BOOLEAN NOT NULL DEFAULT true,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
  `);
  console.log(JSON.stringify({ severity: 'INFO', message: 'DB schema ready' }));
}

initDb().catch(console.error);

module.exports = { pool };
