'use client';

import Link from 'next/link';
import { ShoppingBag, Zap, Shield, Globe } from 'lucide-react';

export default function HomePage() {
  return (
    <div className="bg-white">
      {/* Hero */}
      <section className="relative overflow-hidden bg-gradient-to-br from-blue-600 to-indigo-800 text-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24 text-center">
          <h1 className="text-5xl font-bold tracking-tight mb-6">
            CloudMart
            <span className="block text-blue-200 text-3xl font-normal mt-2">
              Built on Google Cloud Platform
            </span>
          </h1>
          <p className="text-xl text-blue-100 max-w-2xl mx-auto mb-10">
            A production-grade, cloud-native e-commerce platform powered by GKE,
            Cloud Run, Firestore, Cloud SQL, Pub/Sub and more.
          </p>
          <div className="flex justify-center gap-4">
            <Link
              href="/products"
              className="bg-white text-blue-700 px-8 py-3 rounded-lg font-semibold hover:bg-blue-50 transition"
            >
              Browse Products
            </Link>
            <Link
              href="/auth"
              className="border border-white text-white px-8 py-3 rounded-lg font-semibold hover:bg-white/10 transition"
            >
              Sign In
            </Link>
          </div>
        </div>

        {/* GCP badge */}
        <div className="absolute bottom-4 right-6 text-blue-300 text-sm font-mono">
          Hosted on GCP · us-central1
        </div>
      </section>

      {/* GCP Services used */}
      <section className="max-w-7xl mx-auto px-4 py-16">
        <h2 className="text-3xl font-bold text-center text-gray-900 mb-4">
          Powered by Google Cloud
        </h2>
        <p className="text-center text-gray-500 mb-12">
          Every component of CloudMart uses a different GCP managed service
        </p>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { label: 'GKE', desc: 'Product & Order microservices', color: 'bg-blue-100 text-blue-800' },
            { label: 'Cloud Run', desc: 'API Gateway & User Service', color: 'bg-green-100 text-green-800' },
            { label: 'Cloud Functions', desc: 'Image processing & notifications', color: 'bg-yellow-100 text-yellow-800' },
            { label: 'Compute Engine', desc: 'Inventory worker', color: 'bg-orange-100 text-orange-800' },
            { label: 'Firestore', desc: 'Product catalog', color: 'bg-purple-100 text-purple-800' },
            { label: 'Cloud SQL', desc: 'Users & Orders (PostgreSQL)', color: 'bg-red-100 text-red-800' },
            { label: 'Pub/Sub', desc: 'Order lifecycle events', color: 'bg-indigo-100 text-indigo-800' },
            { label: 'Cloud Storage', desc: 'Product images & assets', color: 'bg-pink-100 text-pink-800' },
            { label: 'Memorystore', desc: 'Session cache (Redis)', color: 'bg-teal-100 text-teal-800' },
            { label: 'BigQuery', desc: 'Sales analytics', color: 'bg-cyan-100 text-cyan-800' },
            { label: 'Cloud Armor', desc: 'WAF & DDoS protection', color: 'bg-gray-100 text-gray-800' },
            { label: 'Secret Manager', desc: 'Credentials & keys', color: 'bg-emerald-100 text-emerald-800' },
          ].map((svc) => (
            <div key={svc.label} className="bg-white border border-gray-200 rounded-xl p-4 hover:shadow-md transition">
              <span className={`inline-block px-2 py-1 rounded text-xs font-bold mb-2 ${svc.color}`}>
                {svc.label}
              </span>
              <p className="text-sm text-gray-600">{svc.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section className="bg-gray-50 py-16">
        <div className="max-w-7xl mx-auto px-4">
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                icon: <Zap className="w-8 h-8 text-blue-600" />,
                title: 'Auto-scaling',
                desc: 'GKE HPA scales pods from 2 to 20 based on CPU. Cloud Run scales to zero for cost efficiency.',
              },
              {
                icon: <Shield className="w-8 h-8 text-green-600" />,
                title: 'Production Security',
                desc: 'Cloud Armor WAF, Private GKE nodes, Secret Manager, KMS encryption, IAM least-privilege.',
              },
              {
                icon: <Globe className="w-8 h-8 text-purple-600" />,
                title: 'Cloud-Native',
                desc: 'Fully managed services — no infrastructure to patch. Regional HA with 99.9% SLA target.',
              },
            ].map((f) => (
              <div key={f.title} className="bg-white rounded-xl p-6 shadow-sm">
                <div className="mb-4">{f.icon}</div>
                <h3 className="text-lg font-semibold text-gray-900 mb-2">{f.title}</h3>
                <p className="text-gray-600 text-sm">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="max-w-7xl mx-auto px-4 py-16 text-center">
        <div className="bg-gradient-to-r from-blue-600 to-indigo-700 rounded-2xl p-12 text-white">
          <ShoppingBag className="w-12 h-12 mx-auto mb-4 text-blue-200" />
          <h2 className="text-3xl font-bold mb-4">Ready to shop?</h2>
          <p className="text-blue-100 mb-8 max-w-md mx-auto">
            Explore our catalog of products — orders are processed in real time via Cloud SQL and Pub/Sub.
          </p>
          <Link
            href="/products"
            className="bg-white text-blue-700 px-10 py-3 rounded-lg font-semibold hover:bg-blue-50 transition"
          >
            Shop Now
          </Link>
        </div>
      </section>
    </div>
  );
}
