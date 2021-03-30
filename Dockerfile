FROM <<IMAGE>>


RUN apt-get update && \
   apt-get install -y cmake make g++ flex bison graphviz python && \
   rm -f doxygen2docset.deb && \
   curl -LJO "https://github.com/chinmaygarde/doxygen2docset/releases/download/0.1.1/doxygen2docset.deb" && \
   dpkg -i doxygen2docset.deb
