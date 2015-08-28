FROM heroku/cedar:14

#============= ENV VARS =======================
# Internally, we arbitrarily use port 3000
ENV PORT 3000
ENV PHP_VERSION php-5.6.9
ENV RUBY_VERSION ruby-2.2.3
ENV PYTHON_VERSION python-2.7.10
ENV FREETDS_VERSION freetds-0.91.112
ENV TDSVER 7.0

#============= Intalll TDS ====================

RUN curl -s ftp://ftp.freetds.org/pub/freetds/stable/$FREETEDS_VERSION.tar.gz | tar xvz -C /tmp
WORKDIR /tmp/$FREETEDS_VERSION
RUN ./configure --disable-shared --disable-installed --with-tdsver=7.0 --enable-msdblib --with-gnu-ld
RUN make DESTDIR=/app install
RUN touch /app/$FREETEDS_VERSION/include/tds.h
RUN touch /app/$FREETEDS_VERSION/lib/libtds.a
RUN echo "export PATH=\"/app/usr/local/bin:\$PATH\"" >> /app/.profile.d/freetds.sh

#==========Python Conf==========================

# Add Python binaries to path.
ENV PATH /app/.heroku/python/bin/:$PATH

# Create some needed directories
RUN mkdir -p /app/.heroku/python /app/.profile.d
WORKDIR /app/user

# Install Python
RUN curl -s https://lang-python.s3.amazonaws.com/cedar-14/runtimes/$PYTHON_VERSION.tar.gz | tar zx -C /app/.heroku/python

# Install Pip & Setuptools
RUN curl -s https://bootstrap.pypa.io/get-pip.py | /app/.heroku/python/bin/python

# Export the Python environment variables in .profile.d
RUN echo 'export PATH=$HOME/.heroku/python/bin:$PATH PYTHONUNBUFFERED=true PYTHONHOME=/app/.heroku/python LIBRARY_PATH=/app/.heroku/vendor/lib:/app/.heroku/python/lib:$LIBRARY_PATH LD_LIBRARY_PATH=/app/.heroku/vendor/lib:/app/.heroku/python/lib:$LD_LIBRARY_PATH LANG=${LANG:-en_US.UTF-8} PYTHONHASHSEED=${PYTHONHASHSEED:-random} PYTHONPATH=${PYTHONPATH:-/app/user/}' > /app/.profile.d/python.sh
RUN chmod +x /app/.profile.d/python.sh

#===========Ruby Conf=======================

#Set GEM_PATH
ENV GEM_PATH /app/heroku/ruby/bundle/ruby/2.2.0
ENV GEM_HOME /app/heroku/ruby/bundle/ruby/2.2.0
RUN mkdir -p /app/heroku/ruby/bundle/ruby/2.2.0

# Install Ruby
RUN mkdir -p /app/heroku/ruby/$RUBY_VERSION
RUN curl -s --retry 3 -L https://heroku-buildpack-ruby.s3.amazonaws.com/cedar-14/$RUBY_VERSION.tgz | tar xz -C /app/heroku/ruby/$RUBY_VERSION
ENV PATH /app/heroku/ruby/$RUBY_VERSION/bin:$PATH

# Install Node
RUN curl -s --retry 3 -L http://s3pository.heroku.com/node/v0.12.7/node-v0.12.7-linux-x64.tar.gz | tar xz -C /app/heroku/ruby/
RUN mv /app/heroku/ruby/node-v0.12.7-linux-x64 /app/heroku/ruby/node-0.12.7
ENV PATH /app/heroku/ruby/node-0.12.7/bin:$PATH

# Install Bundler
RUN gem install bundler -v 1.9.10 --no-ri --no-rdoc
ENV PATH /app/user/bin:/app/heroku/ruby/bundle/ruby/2.2.0/bin:$PATH
ENV BUNDLE_APP_CONFIG /app/heroku/ruby/.bundle/config


# export env vars during run time
RUN mkdir -p /app/.profile.d/
RUN echo "cd /app/user/" > /app/.profile.d/home.sh
ONBUILD RUN echo "export PATH=\"$PATH\" GEM_PATH=\"$GEM_PATH\" GEM_HOME=\"$GEM_HOME\" RAILS_ENV=\"\${RAILS_ENV:-$RAILS_ENV}\" SECRET_KEY_BASE=\"\${SECRET_KEY_BASE:-$SECRET_KEY_BASE}\" BUNDLE_APP_CONFIG=\"$BUNDLE_APP_CONFIG\"" > /app/.profile.d/ruby.sh

#============= PHP ===========================

RUN git clone https://github.com/heroku/heroku-buildpack-php /tmp/buildpack
RUN mkdir -p /app/.heroku/php

# Install PHP
RUN curl -Ss https://s3.amazonaws.com/heroku-php/PHP_VERSION.tar.gz | tar xz -C /app/.heroku/php
RUN mkdir -p /app/.heroku/php/etc/php/conf.d
RUN cp /tmp/buildpack/conf/php/php.ini /app/.heroku/php/etc/php
RUN cp /tmp/buildpack/conf/php/php-fpm.conf /app/.heroku/php/etc/php

# Install Ngingx
RUN curl -Ss https://lang-php.s3.amazonaws.com/dist-cedar-master/nginx-1.6.0.tar.gz | tar xz -C /app/.heroku/php
RUN cp /tmp/buildpack/conf/nginx/nginx.conf.default /app/.heroku/php/etc/nginx/nginx.conf

# Install composer
RUN curl -Ss https://getcomposer.org/installer | php -- --install-dir=/app/.heroku/php/bin --filename=composer && chmod +x /app/.heroku/php/bin/composer


# ===== Python ====

ONBUILD ADD requirements.txt /app/user/
ONBUILD RUN /app/.heroku/python/bin/pip install -r requirements.txt
ONBUILD ADD . /app/user/

# ====== Ruby ======

# Run bundler to cache dependencies
ONBUILD COPY ["Gemfile", "Gemfile.lock", "/app/user/"]
ONBUILD RUN bundle install --path /app/heroku/ruby/bundle --jobs 4
ONBUILD ADD . /app/user

# How to conditionally `rake assets:precompile`?
ONBUILD ENV RAILS_ENV production
ONBUILD ENV SECRET_KEY_BASE $(openssl rand -base64 32)
ONBUILD RUN bundle exec rake assets:precompile

# ======== PHP ============
ONBUILD composer.json /app/user
ONBUILD /app/.heroku/php/bin/composer install
ONBUILD ADD . /app/user


# `init` is kept out of /app so it won't be duplicated on Heroku
# Heroku already has a mechanism for running .profile.d scripts,
# so this is just for local parity
COPY ./init.sh /usr/bin/init.sh
RUN chmod +x /usr/bin/init.sh

ENTRYPOINT ["/usr/bin/init.sh"]
