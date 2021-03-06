#######################################################################
#
# Package name: SNPRelate
#
# Description:
#     A High-performance Computing Toolset for Relatedness and
# Principal Component Analysis of SNP Data
#
# Copyright (C) 2011 - 2016        Xiuwen Zheng
# License: GPL-3
# Email: zhengxwen@gmail.com
#


#######################################################################
# Principal Component Analysis
#######################################################################

#######################################################################
# Conduct Principal Component Analysis (PCA)
#

snpgdsPCA <- function(gdsobj, sample.id=NULL, snp.id=NULL,
    autosome.only=TRUE, remove.monosnp=TRUE, maf=NaN, missing.rate=NaN,
    algorithm=c("exact", "randomized"),
    eigen.cnt=ifelse(identical(algorithm, "randomized"), 16L, 32L),
    num.thread=1L, bayesian=FALSE, need.genmat=FALSE,
    genmat.only=FALSE, eigen.method=c("DSPEVX", "DSPEV"),
    aux.dim=eigen.cnt*2L, iter.num=10L, verbose=TRUE)
{
    # check
    ws <- .InitFile2(
        cmd="Principal Component Analysis (PCA) on genotypes:",
        gdsobj=gdsobj, sample.id=sample.id, snp.id=snp.id,
        autosome.only=autosome.only, remove.monosnp=remove.monosnp,
        maf=maf, missing.rate=missing.rate, num.thread=num.thread,
        verbose=verbose)

    stopifnot(is.numeric(eigen.cnt))
    stopifnot(is.logical(bayesian))
    stopifnot(is.logical(need.genmat))
    stopifnot(is.logical(genmat.only))
    algorithm <- match.arg(algorithm)

    if (genmat.only) need.genmat <- TRUE
    if (eigen.cnt <= 0L) eigen.cnt <- ws$n.samp

    eigen.method <- match.arg(eigen.method)
    covalg <- "arith"

    # call parallel PCA
    param <- list(bayesian=bayesian, need.genmat=need.genmat,
        genmat.only=genmat.only, eigen.method=eigen.method, covalg=covalg,
        aux.dim=aux.dim, iter.num=iter.num)
    if (algorithm == "randomized")
        param$aux.mat <- rnorm(aux.dim * ws$n.samp)
    rv <- .Call(gnrPCA, eigen.cnt, algorithm, ws$num.thread, param, verbose)

    # return
    if (algorithm == "exact")
    {
        rv <- list(sample.id = ws$sample.id, snp.id = ws$snp.id,
            eigenval = rv[[3L]], eigenvect = rv[[4L]],
            varprop = rv[[3L]] / rv[[5L]],
            TraceXTX = rv[[1L]], Bayesian = bayesian, genmat = rv[[2L]])
        class(rv) <- "snpgdsPCAClass"
    } else if (algorithm == "randomized")
    {
        rv <- list(sample.id = ws$sample.id, snp.id = ws$snp.id,
            eigenval = rv[[1L]], eigenvect = t(rv[[2]][seq_len(eigen.cnt), ]),
            varprop = NaN,
            TraceXTX = NaN, Bayesian = FALSE)
        class(rv) <- "snpgdsPCAClass"
    }
    return(rv)
}



#######################################################################
# To calculate SNP correlations from principal component analysis
#

snpgdsPCACorr <- function(pcaobj, gdsobj, snp.id=NULL, eig.which=NULL,
    num.thread=1L, verbose=TRUE)
{
    # check
    stopifnot(inherits(pcaobj, "snpgdsPCAClass"))
    ws <- .InitFile(gdsobj, sample.id=pcaobj$sample.id, snp.id=snp.id,
        with.id=TRUE)

    stopifnot(is.numeric(num.thread), num.thread>0L)
    if (length(pcaobj$sample.id) != nrow(pcaobj$eigenvect))
    {
        stop("Internal error: ",
            "the number of samples should be ",
            "equal to the number of rows in 'eigenvect'.")
    }
    stopifnot(is.logical(verbose))

    if (is.null(eig.which))
    {
        eig.which <- 1:dim(pcaobj$eigenvect)[2]
    } else {
        stopifnot(is.vector(eig.which))
        stopifnot(is.numeric(eig.which))
        eig.which <- as.integer(eig.which)
    }

    if (verbose)
    {
        cat("SNP correlation:\n")
        cat("Working space:", ws$n.samp, "samples,", ws$n.snp, "SNPs\n");
        cat("    using ", num.thread, " (CPU) core", .plural(num.thread), "\n",
            sep="")
        cat("    using the top", dim(pcaobj$eigenvect)[2], "eigenvectors\n")
    }

    # call C function
    rv <- .Call(gnrPCACorr, length(eig.which), pcaobj$eigenvect[,eig.which],
        num.thread, verbose)

    # return
    list(sample.id=pcaobj$sample.id, snp.id=ws$snp.id, snpcorr=rv)
}



#######################################################################
# To calculate SNP loadings from principal component analysis
#

snpgdsPCASNPLoading <- function(pcaobj, gdsobj, num.thread=1L, verbose=TRUE)
{
    # check
    stopifnot(inherits(pcaobj, "snpgdsPCAClass"))
    ws <- .InitFile(gdsobj, sample.id=pcaobj$sample.id, snp.id=pcaobj$snp.id)
    stopifnot(is.numeric(num.thread), num.thread > 0L)
    stopifnot(is.logical(verbose))

    if (verbose)
    {
        cat("SNP loading:\n")
        cat("Working space:", ws$n.samp, "samples,", ws$n.snp, "SNPs\n");
        cat("    using ", num.thread, " (CPU) core", .plural(num.thread), "\n",
            sep="")
        cat("    using the top", dim(pcaobj$eigenvect)[2], "eigenvectors\n")
    }

    # call parallel PCA
    rv <- .Call(gnrPCASNPLoading, pcaobj$eigenval, ncol(pcaobj$eigenvect),
        pcaobj$eigenvect, pcaobj$TraceXTX, num.thread, pcaobj$Bayesian,
        verbose)

    # return
    rv <- list(sample.id=pcaobj$sample.id, snp.id=pcaobj$snp.id,
        eigenval=pcaobj$eigenval, snploading=rv[[1]],
        TraceXTX=pcaobj$TraceXTX, Bayesian=pcaobj$Bayesian,
        avefreq=rv[[2]], scale=rv[[3]])
    class(rv) <- "snpgdsPCASNPLoadingClass"
    return(rv)
}



#######################################################################
# To calculate sample loadings from SNP loadings in PCA
#

snpgdsPCASampLoading <- function(loadobj, gdsobj, sample.id=NULL,
    num.thread=1L, verbose=TRUE)
{
    # check
    stopifnot(inherits(loadobj, "snpgdsPCASNPLoadingClass"))
    ws <- .InitFile(gdsobj, sample.id=sample.id, snp.id=loadobj$snp.id)

    sample.id <- read.gdsn(index.gdsn(gdsobj, "sample.id"))
    if (!is.null(ws$samp.flag))
        sample.id <- sample.id[ws$samp.flag]
    stopifnot(is.numeric(num.thread), length(num.thread)==1L)
    stopifnot(is.logical(verbose), length(verbose)==1L)

    eigcnt <- nrow(loadobj$snploading)
    if (verbose)
    {
        cat("Sample loading:\n")
        cat("Working space:", ws$n.samp, "samples,", ws$n.snp, "SNPs\n")
        cat("    using ", num.thread, " (CPU) core", .plural(num.thread), "\n",
            sep="")
        cat("    using the top", eigcnt, "eigenvectors\n")
    }

    # prepare post-eigenvectors
    ss <- (length(loadobj$sample.id) - 1) / loadobj$TraceXTX
    sqrt_eigval <- sqrt(ss / loadobj$eigenval[1:eigcnt])
    sload <- loadobj$snploading * sqrt_eigval

    # call C function
    rv <- .Call(gnrPCASampLoading, eigcnt, sload, loadobj$avefreq,
        loadobj$scale, num.thread, verbose)

    # return
    rv <- list(sample.id = sample.id, snp.id = loadobj$snp.id,
        eigenval = loadobj$eigenval, eigenvect = rv,
        TraceXTX = loadobj$TraceXTX,
        Bayesian = loadobj$Bayesian, genmat = NULL)
    class(rv) <- "snpgdsPCAClass"
    return(rv)
}



#######################################################################
# Eigen-Analysis on genotypes
#

snpgdsEIGMIX <- function(gdsobj, sample.id=NULL, snp.id=NULL,
    autosome.only=TRUE, remove.monosnp=TRUE, maf=NaN, missing.rate=NaN,
    num.thread=1L, eigen.cnt=32L, need.ibdmat=FALSE, ibdmat.only=FALSE,
    verbose=TRUE)
{
    # check and initialize ...
    ws <- .InitFile2(cmd="Eigen-analysis on genotypes:",
        gdsobj=gdsobj, sample.id=sample.id, snp.id=snp.id,
        autosome.only=autosome.only, remove.monosnp=remove.monosnp,
        maf=maf, missing.rate=missing.rate, num.thread=num.thread,
        verbose=verbose)

    stopifnot(is.numeric(eigen.cnt), length(eigen.cnt)==1L)
    if (eigen.cnt < 1L)
        eigen.cnt <- ws$n.samp

    stopifnot(is.logical(need.ibdmat), length(need.ibdmat)==1L)
    stopifnot(is.logical(ibdmat.only), length(ibdmat.only)==1L)

    # call eigen-analysis
    rv <- .Call(gnrEIGMIX, eigen.cnt, ws$num.thread, need.ibdmat, ibdmat.only,
        verbose)

    # return
    rv <- list(sample.id = ws$sample.id, snp.id = ws$snp.id,
        eigenval = rv$eigenval, eigenvect = rv$eigenvect,
        ibdmat = rv$ibdmat)
    class(rv) <- "snpgdsEigMixClass"
    return(rv)
}



#######################################################################
# Admixture proportion from eigen-analysis
#

snpgdsAdmixProp <- function(eigobj, groups, bound=FALSE)
{
    # check
    stopifnot( inherits(eigobj, "snpgdsEigMixClass") |
        inherits(eigobj, "snpgdsPCAClass") )
    # 'sample.id' and 'eigenvect' should exist
    stopifnot(!is.null(eigobj$sample.id))
    stopifnot(is.matrix(eigobj$eigenvect))

    stopifnot(is.list(groups))
    stopifnot(length(groups) > 1)
    if (length(groups) > (ncol(eigobj$eigenvect)+1))
    {
        stop("`eigobj' should have more eigenvectors than ",
            "what is specified in `groups'.")
    }

    grlist <- NULL
    for (i in 1:length(groups))
    {
        if (!is.vector(groups[[i]]) & !is.factor(groups[[i]]))
        {
            stop(
                "`groups' should be a list of sample IDs ",
                "with respect to multiple groups."
            )
        }
        if (any(!(groups[[i]] %in% eigobj$sample.id)))
        {
            stop(sprintf(
                "`groups[[%d]]' includes sample(s) not existing ",
                "in `eigobj$sample.id'.", i))
        }

        if (any(groups[[i]] %in% grlist))
            warning("There are some overlapping between group sample IDs.")
        grlist <- c(grlist, groups[[i]])
    }

    stopifnot(is.logical(bound) & is.vector(bound))
    stopifnot(length(bound) == 1)

    # calculate ...

    E <- eigobj$eigenvect[, 1:(length(groups)-1)]
    if (is.vector(E)) E <- matrix(E, ncol=1)
    mat <- NULL
    for (i in 1:length(groups))
    {
        k <- match(groups[[i]], eigobj$sample.id)
        Ek <- E[k, ]
        if (is.vector(Ek))
            mat <- rbind(mat, mean(Ek))
        else
            mat <- rbind(mat, colMeans(Ek))
    }

    # check
    if (any(is.na(mat)))
        stop("The eigenvectors should not have missing value!")

    T.P <- mat[length(groups), ]
    T.R <- solve(mat[-length(groups), ] -
        matrix(T.P, nrow=length(T.P), ncol=length(T.P), byrow=TRUE))

    new.p <- (E - matrix(T.P, nrow=dim(E)[1], ncol=length(T.P),
        byrow=TRUE)) %*% T.R
    new.p <- cbind(new.p, 1 - rowSums(new.p))
    colnames(new.p) <- names(groups)
    rownames(new.p) <- eigobj$sample.id

    # whether bounded
    if (bound)
    {
        new.p[new.p < 0] <- 0
        r <- 1.0 / rowSums(new.p)
        new.p <- new.p * r
    }

    new.p
}



#######################################################################
# plot PCA results
#

plot.snpgdsPCAClass <- function(x, eig=c(1L,2L), ...)
{
    stopifnot(inherits(x, "snpgdsPCAClass"))
    stopifnot(is.numeric(eig), length(eig) >= 2L)

    if (length(eig) == 2L)
    {
        v <- x$varprop[eig] * 100
        plot(x$eigenvect[,eig[1L]], x$eigenvect[,eig[2L]],
            xlab=sprintf("Eigenvector %d (%.1f%%)", eig[1L], v[eig[1L]]),
            ylab=sprintf("Eigenvector %d (%.1f%%)", eig[2L], v[eig[2L]]),
            ...)
    } else {
        pairs(x$eigenvect[, eig],
            labels=sprintf("Eig %d\n(%.1f%%)", eig, x$varprop[eig]*100),
            gap=0.2, ...)
    }

    invisible()
}
