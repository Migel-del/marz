FROM nginx:latest

# Create the directory if it doesn't exist.  Good practice for robustness
RUN mkdir -p /etc/nginx/conf.d

# Copy your nginx configuration file into the correct location for Nginx.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose the port Nginx will listen on.
EXPOSE 8080

# Crucial for Cloud Run: Run Nginx in the foreground, preventing it from forking to the background.
CMD ["nginx", "-g", "daemon off;"]
