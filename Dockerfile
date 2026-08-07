FROM nginx:alpine
COPY index.html dashboard.html app.js style.css sw.js manifest.json icon-192.png icon-512.png /usr/share/nginx/html/
EXPOSE 80
