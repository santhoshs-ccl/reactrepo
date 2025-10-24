# Use Node.js official image
FROM node:24.1.0-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy all source files
COPY . .

# Expose React default port
EXPOSE 3000

# Start React dev server
CMD ["npm", "start"]
