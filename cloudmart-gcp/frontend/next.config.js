/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',  // Enables Cloud Run deployment
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'storage.googleapis.com' },
      { protocol: 'https', hostname: '*.r2.cloudflarestorage.com' },  // for AWS S3 after migration
    ],
  },
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'https://api.cloudmart.demo',
  },
};

module.exports = nextConfig;
