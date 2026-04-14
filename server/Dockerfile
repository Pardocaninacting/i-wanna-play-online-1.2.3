FROM node:21-alpine3.18
RUN mkdir -p /home/node/app/node_modules && chown -R node:node /home/node/app
WORKDIR /home/node/app
COPY --chown=node:node package*.json ./
USER node
RUN npm install
COPY --chown=node:node . .
RUN npm run build
EXPOSE ${PORT_HTTP}
EXPOSE ${PORT_SOCKETS}
EXPOSE ${PORT_SOCKETS_UDP}
CMD npm start
