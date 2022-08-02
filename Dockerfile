ARG RUBY_VERSION

FROM dreg.sbmt.io/dhub/library/ruby:$RUBY_VERSION

ENV BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

RUN gem update --system
