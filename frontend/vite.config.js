import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rolldownOptions: {
      output: {
        // Separa o bundle em pedacos menores (todos continuam carregando na
        // abertura): o modelo (forest.json, ~370 KB) e as bibliotecas
        // (React, cliente MQTT) mudam em ritmos diferentes do codigo do app.
        codeSplitting: {
          groups: [
            { name: 'modelo', test: /[\\/]src[\\/]model[\\/]forest\.json$/ },
            { name: 'react', test: /[\\/]node_modules[\\/](react|react-dom|scheduler)[\\/]/ },
            { name: 'vendor', test: /[\\/]node_modules[\\/]/ },
          ],
        },
      },
    },
  },
})
