import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],server: {
    host: true,
    allowedHosts: ["4097-2804-7f5-f216-29f-9b94-5abd-669a-45b1.ngrok-free.app"],
  },
})
