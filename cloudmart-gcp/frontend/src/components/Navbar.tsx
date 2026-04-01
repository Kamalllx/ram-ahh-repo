'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ShoppingBag, ShoppingCart, User, LogOut } from 'lucide-react';
import { useEffect, useState } from 'react';

export default function Navbar() {
  const pathname = usePathname();
  const [loggedIn, setLoggedIn] = useState(false);

  useEffect(() => {
    setLoggedIn(!!localStorage.getItem('cloudmart_token'));
  }, [pathname]);

  function logout() {
    localStorage.removeItem('cloudmart_token');
    window.location.href = '/';
  }

  const navLink = (href: string, label: string) => (
    <Link
      href={href}
      className={`text-sm font-medium transition ${
        pathname === href
          ? 'text-blue-600 border-b-2 border-blue-600 pb-0.5'
          : 'text-gray-600 hover:text-gray-900'
      }`}
    >
      {label}
    </Link>
  );

  return (
    <nav className="bg-white border-b border-gray-200 sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 font-bold text-xl text-blue-600">
            <ShoppingBag className="w-6 h-6" />
            CloudMart
          </Link>

          {/* Nav links */}
          <div className="hidden md:flex items-center gap-8">
            {navLink('/products', 'Products')}
            {loggedIn && navLink('/orders', 'My Orders')}
          </div>

          {/* Auth */}
          <div className="flex items-center gap-3">
            {loggedIn ? (
              <>
                <Link href="/cart" className="relative p-2 text-gray-600 hover:text-gray-900">
                  <ShoppingCart className="w-5 h-5" />
                </Link>
                <Link href="/profile" className="p-2 text-gray-600 hover:text-gray-900">
                  <User className="w-5 h-5" />
                </Link>
                <button
                  onClick={logout}
                  className="p-2 text-gray-600 hover:text-red-600 transition"
                  title="Logout"
                >
                  <LogOut className="w-5 h-5" />
                </button>
              </>
            ) : (
              <Link
                href="/auth"
                className="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-blue-700 transition"
              >
                Sign In
              </Link>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
