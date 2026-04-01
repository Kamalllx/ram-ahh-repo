'use strict';

// Structured JSON logging compatible with Google Cloud Logging
const logger = {
  _log(severity, data) {
    const entry = {
      severity,
      timestamp: new Date().toISOString(),
      ...(typeof data === 'string' ? { message: data } : data),
    };
    process.stdout.write(JSON.stringify(entry) + '\n');
  },
  info:  (data) => logger._log('INFO', data),
  warn:  (data) => logger._log('WARNING', data),
  error: (data) => logger._log('ERROR', data),
  debug: (data) => process.env.LOG_LEVEL === 'debug' && logger._log('DEBUG', data),
};

module.exports = { logger };
