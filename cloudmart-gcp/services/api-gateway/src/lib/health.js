'use strict';

const axios = require('axios');

async function healthCheck(req, res) {
  const checks = {};
  let healthy = true;

  const services = [
    { name: 'product_service', url: `${process.env.PRODUCT_SERVICE_URL}/health` },
    { name: 'order_service',   url: `${process.env.ORDER_SERVICE_URL}/health` },
    { name: 'user_service',    url: `${process.env.USER_SERVICE_URL}/health` },
  ];

  await Promise.allSettled(
    services.map(async ({ name, url }) => {
      try {
        await axios.get(url, { timeout: 3000 });
        checks[name] = 'ok';
      } catch {
        checks[name] = 'degraded';
        healthy = false;
      }
    }),
  );

  res.status(healthy ? 200 : 207).json({
    status: healthy ? 'ok' : 'degraded',
    service: 'api-gateway',
    version: process.env.npm_package_version || '1.0.0',
    uptime: process.uptime(),
    checks,
    timestamp: new Date().toISOString(),
  });
}

module.exports = { healthCheck };
