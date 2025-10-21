# Dockerfile
FROM nginx:alpine

# Copy the landing page folder into Nginx's default HTML directory
COPY landing_page/ /usr/share/nginx/html/

# Expose port 80
EXPOSE 80

# Keep Nginx running in the foreground
CMD ["nginx", "-g", "daemon off;"]
