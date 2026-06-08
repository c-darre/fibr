cat > Procfile << 'EOF'
web: bin/rails server -p ${PORT:-5000} -e $RAILS_ENV
worker: bin/jobs
EOF
