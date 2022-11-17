ARG RUBY_VERSION

FROM dreg.sbmt.io/dhub/library/ruby:$RUBY_VERSION

ARG BUNDLER_VERSION

ENV BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

RUN gem update --system \
  && gem install bundler -v ${BUNDLER_VERSION}
