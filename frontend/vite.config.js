import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rolldownOptions: {
      output: {
        // Separa o bundle em pedacos menores (todos continuam carregando na
        // abertura): as bibliotecas (React, cliente MQTT) mudam em ritmos
        // diferentes do codigo do painel. O modelo (forest.json) nao entra no
        // site: quem roda e a pulseira (src/modelMeta.js le so o "meta").
        codeSplitting: {
          groups: [
            { name: 'react', test: /[\\/]node_modules[\\/](react|react-dom|scheduler)[\\/]/ },
            { name: 'vendor', test: /[\\/]node_modules[\\/]/ },
          ],
        },
      },
    },
  },
})
