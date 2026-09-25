import { app } from './app';
import { config } from './config/index';
import { initDb, pool } from './db/index';
import { logger } from './utils/logger';

let server: ReturnType<typeof app.listen>;

async function start() {
  try {
    await initDb();
    server = app.listen(config.port, () => {
      logger.info(`TaskFlow running on port ${config.port}`);
    });
  } catch (err: any) {
    logger.error('Failed to start application', { error: err.message });
    process.exit(1);
  }
}

const gracefulShutdown = async (signal: string) => {
  logger.info(`Received ${signal}. Shutting down gracefully...`);
  if (server) {
    server.close(async () => {
      logger.info('HTTP server closed.');
      await pool.end();
      logger.info('Database pool drained.');
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

start();