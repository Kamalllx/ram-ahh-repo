import axios from 'axios';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'https://api.cloudmart.demo';

export const api = axios.create({
  baseURL: `${API_BASE}/api/v1`,
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

// Attach JWT token to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('cloudmart_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Handle 401 → clear token and redirect to login
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('cloudmart_token');
      window.location.href = '/auth';
    }
    return Promise.reject(err);
  },
);

// ── Auth ──────────────────────────────────────────────────────
export const authApi = {
  register: (data: { email: string; password: string; full_name: string; phone?: string }) =>
    api.post('/users/register', data),
  login: (data: { email: string; password: string }) =>
    api.post('/users/login', data),
  getProfile: () =>
    api.get('/users/profile'),
};

// ── Products ──────────────────────────────────────────────────
export const productsApi = {
  list: (params?: {
    category?: string;
    min_price?: number;
    max_price?: number;
    in_stock?: boolean;
    page?: number;
    page_size?: number;
  }) => api.get('/products', { params }),

  search: (q: string, page = 1) =>
    api.get('/products/search', { params: { q, page } }),

  get: (id: string) =>
    api.get(`/products/${id}`),
};

// ── Orders ────────────────────────────────────────────────────
export const ordersApi = {
  list: (params?: { status?: string; page?: number }) =>
    api.get('/orders', { params }),

  get: (id: string) =>
    api.get(`/orders/${id}`),

  create: (data: {
    items: Array<{ product_id: string; product_name: string; quantity: number; unit_price: number }>;
    shipping_address: object;
    payment_method: string;
  }) => api.post('/orders', data),

  cancel: (id: string) =>
    api.patch(`/orders/${id}/cancel`),
};

// ── Upload ────────────────────────────────────────────────────
export const uploadApi = {
  productImage: (file: File) => {
    const form = new FormData();
    form.append('image', file);
    return api.post('/upload/product-image', form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
};
