# Use Node.js official image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Expose the port that Vite uses
EXPOSE 3002

# Start the development server
CMD ["npm", "run", "start", "--", "--host", "0.0.0.0", "--port", "3002"]
