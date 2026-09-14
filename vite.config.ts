import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],server: {
    host: true,
    allowedHosts: ["a836-2804-7f5-f216-29f-c63a-8e41-9f53-c26e.ngrok-free.app"],
  },
})
