FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js accounts.js ./
COPY public ./public
ENV PORT=3000
ENV DATA_DIR=/tmp/wobble-data
RUN mkdir -p /data && chown node:node /data
EXPOSE 3000
USER node
CMD ["node", "server.js"]
