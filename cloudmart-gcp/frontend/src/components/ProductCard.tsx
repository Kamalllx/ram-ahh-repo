'use client';

import Link from 'next/link';
import Image from 'next/image';
import { ShoppingCart, Star } from 'lucide-react';
import toast from 'react-hot-toast';

interface Product {
  id: string;
  name: string;
  description: string;
  price: number;
  category: string;
  images: Array<{ url: string; alt: string }>;
  stock_quantity: number;
  rating_avg: number;
  rating_count: number;
}

export default function ProductCard({ product }: { product: Product }) {
  const image = product.images?.[0];
  const inStock = product.stock_quantity > 0;

  function addToCart() {
    const cart = JSON.parse(localStorage.getItem('cloudmart_cart') || '[]');
    const existing = cart.find((i: { id: string }) => i.id === product.id);
    if (existing) {
      existing.quantity += 1;
    } else {
      cart.push({ id: product.id, name: product.name, price: product.price, quantity: 1 });
    }
    localStorage.setItem('cloudmart_cart', JSON.stringify(cart));
    toast.success(`${product.name} added to cart`);
  }

  return (
    <div className="bg-white border border-gray-200 rounded-xl overflow-hidden hover:shadow-md transition group">
      {/* Image */}
      <Link href={`/products/${product.id}`} className="block relative aspect-square bg-gray-100">
        {image ? (
          <Image
            src={image.url}
            alt={image.alt || product.name}
            fill
            className="object-cover group-hover:scale-105 transition duration-300"
            sizes="(max-width: 768px) 50vw, 25vw"
          />
        ) : (
          <div className="flex items-center justify-center h-full">
            <ShoppingCart className="w-12 h-12 text-gray-300" />
          </div>
        )}

        {!inStock && (
          <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
            <span className="bg-white text-gray-800 text-xs font-bold px-3 py-1 rounded-full">
              Out of Stock
            </span>
          </div>
        )}
      </Link>

      {/* Info */}
      <div className="p-4">
        <span className="text-xs text-blue-600 font-medium uppercase tracking-wide">
          {product.category}
        </span>
        <Link href={`/products/${product.id}`}>
          <h3 className="font-semibold text-gray-900 mt-1 mb-1 line-clamp-2 hover:text-blue-600 transition">
            {product.name}
          </h3>
        </Link>

        {product.rating_count > 0 && (
          <div className="flex items-center gap-1 mb-2">
            <Star className="w-3.5 h-3.5 text-yellow-400 fill-yellow-400" />
            <span className="text-xs text-gray-600">
              {product.rating_avg.toFixed(1)} ({product.rating_count})
            </span>
          </div>
        )}

        <div className="flex items-center justify-between mt-3">
          <span className="text-lg font-bold text-gray-900">
            ${product.price.toFixed(2)}
          </span>
          <button
            onClick={addToCart}
            disabled={!inStock}
            className="flex items-center gap-1.5 bg-blue-600 text-white text-sm px-3 py-1.5 rounded-lg hover:bg-blue-700 disabled:opacity-40 disabled:cursor-not-allowed transition"
          >
            <ShoppingCart className="w-4 h-4" />
            Add
          </button>
        </div>
      </div>
    </div>
  );
}
