# ---- Build Stage ----
FROM node:22.22.0-alpine3.22 AS builder

# Set the working directory in the container to /console
WORKDIR /console

# Create the pnpm directory and set the PNPM_HOME environment variable
RUN mkdir -p ~/.pnpm
ENV PNPM_HOME=/root/.pnpm

# Set environment
ARG ENVIRONMENT=production

# Attribution
ARG DISABLE_FLEETBASE_ATTRIBUTION=false
ENV DISABLE_FLEETBASE_ATTRIBUTION=$DISABLE_FLEETBASE_ATTRIBUTION

# Add the pnpm global bin to the PATH
ENV PATH=/root/.pnpm/bin:$PATH

# Copy package metadata first for better dependency caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# Copy over .npmrc if applicable
COPY .npmr[c] ./

# Install global dependencies
# pnpm is pinned to the "packageManager" version in package.json. The latest pnpm would switch
# to that version by downloading a native pnpm executable, which fails silently on some
# platforms (e.g. Alpine on Apple Silicon); the npm package itself is plain JavaScript.
RUN npm install -g ember-cli "pnpm@$(node -p "require('./package.json').packageManager.split('@')[1]")"

# Install git
RUN apk update && apk add git openssh-client

# Trust GitHub's host keys, for any dependency fetched over git+ssh. None are today, so a
# network that blocks SSH to GitHub (port 22) must not fail the build.
RUN mkdir -p -m 0700 ~/.ssh && \
    (ssh-keyscan -T 10 github.com >> ~/.ssh/known_hosts || echo "Warning: could not reach github.com over SSH; skipping its host key.")

# Install app dependencies
RUN pnpm install --frozen-lockfile

# Copy the console directory contents into the container at /console
COPY . .

# Build the application
RUN pnpm build --environment $ENVIRONMENT

# ---- Serve Stage ----
FROM nginx:alpine

# Copy the built app to our served directory
COPY --from=builder /console/dist /usr/share/nginx/html

# Expose the port nginx is bound to
EXPOSE 4200

# Use custom nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]
