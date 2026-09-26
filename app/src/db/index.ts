import { Pool } from 'pg';
import { config } from '../config/index';
import { logger } from '../utils/logger';

export const pool = new Pool({
  connectionString: config.databaseUrl,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
  ssl: {
    rejectUnauthorized: false, 
  },
});

pool.on('error', (err) => {
  logger.error('Unexpected database client error', { error: err.message });
});

export const initDb = async (): Promise<void> => {
  const query = `
    CREATE TABLE IF NOT EXISTS tasks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      title VARCHAR(255) NOT NULL,
      description TEXT,
      status VARCHAR(50) DEFAULT 'PENDING',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
  `;
  await pool.query(query);
  logger.info('Database schema initialized');
};