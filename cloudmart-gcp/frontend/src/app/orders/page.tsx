'use client';

import { useEffect, useState } from 'react';
import { ordersApi } from '@/lib/api';
import { Package, Clock, CheckCircle, Truck, XCircle } from 'lucide-react';
import toast from 'react-hot-toast';

const STATUS_CONFIG: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  pending:    { label: 'Pending',    icon: <Clock className="w-4 h-4" />,        color: 'text-yellow-600 bg-yellow-50' },
  confirmed:  { label: 'Confirmed',  icon: <CheckCircle className="w-4 h-4" />,  color: 'text-blue-600 bg-blue-50' },
  processing: { label: 'Processing', icon: <Package className="w-4 h-4" />,      color: 'text-indigo-600 bg-indigo-50' },
  shipped:    { label: 'Shipped',    icon: <Truck className="w-4 h-4" />,        color: 'text-green-600 bg-green-50' },
  delivered:  { label: 'Delivered',  icon: <CheckCircle className="w-4 h-4" />,  color: 'text-green-700 bg-green-100' },
  cancelled:  { label: 'Cancelled',  icon: <XCircle className="w-4 h-4" />,      color: 'text-red-600 bg-red-50' },
};

interface Order {
  id: string;
  status: string;
  total_amount: number;
  currency: string;
  items: Array<{ product_name: string; quantity: number; unit_price: number }>;
  created_at: string;
  tracking_number: string | null;
}

export default function OrdersPage() {
  const [orders, setOrders]   = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    ordersApi.list()
      .then((res) => setOrders(res.data))
      .catch(() => toast.error('Failed to load orders'))
      .finally(() => setLoading(false));
  }, []);

  async function cancel(id: string) {
    try {
      await ordersApi.cancel(id);
      setOrders((prev) =>
        prev.map((o) => (o.id === id ? { ...o, status: 'cancelled' } : o)),
      );
      toast.success('Order cancelled');
    } catch {
      toast.error('Could not cancel order');
    }
  }

  if (loading) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8">
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="bg-gray-200 h-32 rounded-xl animate-pulse" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">My Orders</h1>

      {orders.length === 0 ? (
        <div className="text-center py-16 text-gray-500">
          <Package className="w-12 h-12 mx-auto mb-4 text-gray-300" />
          <p className="text-lg mb-2">No orders yet</p>
          <a href="/products" className="text-blue-600 hover:underline text-sm">
            Browse products →
          </a>
        </div>
      ) : (
        <div className="space-y-4">
          {orders.map((order) => {
            const status = STATUS_CONFIG[order.status] || STATUS_CONFIG.pending;
            return (
              <div key={order.id} className="bg-white border border-gray-200 rounded-xl p-6">
                <div className="flex items-start justify-between mb-4">
                  <div>
                    <p className="text-sm text-gray-500 mb-1">
                      Order #{order.id.slice(-8).toUpperCase()}
                    </p>
                    <p className="text-xs text-gray-400">
                      {new Date(order.created_at).toLocaleDateString('en-US', {
                        year: 'numeric', month: 'long', day: 'numeric',
                      })}
                    </p>
                  </div>
                  <div className="text-right">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium ${status.color}`}>
                      {status.icon}
                      {status.label}
                    </span>
                    <p className="text-lg font-bold text-gray-900 mt-2">
                      ${order.total_amount.toFixed(2)}
                    </p>
                  </div>
                </div>

                {/* Items */}
                <div className="space-y-1 mb-4">
                  {order.items.map((item, i) => (
                    <div key={i} className="flex justify-between text-sm text-gray-600">
                      <span>{item.product_name} × {item.quantity}</span>
                      <span>${(item.unit_price * item.quantity).toFixed(2)}</span>
                    </div>
                  ))}
                </div>

                {order.tracking_number && (
                  <p className="text-sm text-gray-500">
                    Tracking: <span className="font-mono">{order.tracking_number}</span>
                  </p>
                )}

                {['pending', 'confirmed'].includes(order.status) && (
                  <button
                    onClick={() => cancel(order.id)}
                    className="mt-4 text-sm text-red-600 hover:underline"
                  >
                    Cancel order
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
