import numpy as np
cimport cython
ctypedef fused floating:
    cython.double
    cython.float

ctypedef fused integral:
    cython.short
    cython.int
    cython.longlong

ctypedef fused number:
    cython.double
    cython.float
    cython.short
    cython.int
    cython.longlong

cdef extern from "math.h":
    double sqrt(double x) nogil
    double floor (double x) nogil

cdef inline int ifloor(double x) nogil:
    return int(floor(x))

cdef inline __apply_affine_3d_x0(number x0, number x1, number x2, floating[:,:] affine):
    return affine[0,0]*x0 + affine[0,1]*x1 + affine[0,2]*x2 + affine[0,3]

cdef inline __apply_affine_3d_x1(number x0, number x1, number x2, floating[:,:] affine):
    return affine[1,0]*x0 + affine[1,1]*x1 + affine[1,2]*x2 + affine[1,3]

cdef inline __apply_affine_3d_x2(number x0, number x1, number x2,  floating[:,:] affine):
    return affine[2,0]*x0 + affine[2,1]*x1 + affine[2,2]*x2 + affine[2,3]

cdef inline __apply_affine_2d_x0(number x0, number x1, floating[:,:] affine):
    return affine[0,0]*x0 + affine[0,1]*x1 + affine[0,2]

cdef inline __apply_affine_2d_x1(number x0, number x1, floating[:,:] affine):
    return affine[1,0]*x0 + affine[1,1]*x1 + affine[1,2]

########################################################################
#############displacement field composition and inversion###############
########################################################################
@cython.boundscheck(False)
@cython.wraparound(False) 
@cython.cdivision(True)
cdef void __compose_vector_fields(floating[:,:,:] d1, floating[:,:,:] d2, floating[:,:,:] comp, floating[:] stats) nogil:
    cdef int nr1=d1.shape[0]
    cdef int nc1=d1.shape[1]
    cdef int nr2=d2.shape[0]
    cdef int nc2=d2.shape[1]
    cdef floating maxNorm=0
    cdef floating meanNorm=0
    cdef floating stdNorm=0
    cdef floating nn
    cdef int cnt=0
    cdef int i,j,ii,jj
    cdef floating dii, djj, alpha, beta, calpha, cbeta
    for i in range(nr1):
        for j in range(nc1):
            dii=i+d1[i,j,0]
            djj=j+d1[i,j,1]
            if((dii < 0) or (nr2-1 < dii) or (djj < 0) or (nc2-1 < djj)):
                continue
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii < 0) or (nr2 <= ii) or (jj < 0) or (nc2 <= jj) ):
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            comp[i,j,:]=d1[i,j,:]
            #---top-left
            comp[i,j,0]+=alpha*beta*d2[ii,jj,0]
            comp[i,j,1]+=alpha*beta*d2[ii,jj,1]
            #---top-right
            jj+=1
            if(jj < nc2):
                comp[i,j,0]+=alpha*cbeta*d2[ii,jj,0]
                comp[i,j,1]+=alpha*cbeta*d2[ii,jj,1]
            #---bottom-right
            ii+=1
            if((ii >= 0) and (jj >= 0) and (ii < nr2)and (jj < nc2)):
                comp[i,j,0]+=calpha*cbeta*d2[ii,jj,0]
                comp[i,j,1]+=calpha*cbeta*d2[ii,jj,1]
            #---bottom-left
            jj-=1
            if((ii >= 0) and (jj >= 0) and (ii < nr2) and (jj < nc2)):
                comp[i,j,0]+=d2[ii,jj,0]
                comp[i,j,1]+=d2[ii,jj,1]
            #consider only displacements that land inside the image
            if(((dii >= 0) and (dii <= nr2-1)) and ((djj >= 0) and (djj <= nc2-1))):
                nn=comp[i,j,0]**2+comp[i,j,1]**2
                if(maxNorm < nn):
                    maxNorm=nn
                meanNorm+=nn
                stdNorm+=nn*nn
                cnt+=1
    meanNorm/=cnt
    stats[0]=sqrt(maxNorm)
    stats[1]=sqrt(meanNorm)
    stats[2]=sqrt(stdNorm/cnt - meanNorm*meanNorm)

def compose_vector_fields(floating[:,:,:] d1, floating[:,:,:] d2):
    cdef floating[:,:,:] comp=np.zeros_like(d1)
    cdef floating[:] stats=np.zeros(shape=(3,), dtype=cython.typeof(d1[0,0,0]))
    __compose_vector_fields(d1, d2, comp, stats)
    return comp, stats

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void __compose_vector_fields_3d(floating[:,:,:,:] d1, floating[:,:,:,:] d2, floating[:,:,:,:] comp, floating[:] stats) nogil:
    cdef int ns1=d1.shape[0]
    cdef int nr1=d1.shape[1]
    cdef int nc1=d1.shape[2]
    cdef int ns2=d2.shape[0]
    cdef int nr2=d2.shape[1]
    cdef int nc2=d2.shape[2]
    cdef floating maxNorm=0
    cdef floating meanNorm=0
    cdef floating stdNorm=0
    cdef int k,i,j, kk, ii, jj
    cdef floating dkk, dii, djj
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma, nn
    cdef int cnt=0
    for k in range(ns1):
        for i in range(nr1):
            for j in range(nc1):
                dkk=k+d1[k,i,j,0]
                dii=i+d1[k,i,j,1]
                djj=j+d1[k,i,j,2]
                if((dii<0) or (djj<0) or (dkk<0) or (dii>nr2-1) or (djj>nc2-1) or (dkk>ns2-1)):
                    continue
                #---top-left
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nr2) or (jj>=nc2) or (kk>=ns2)):
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                comp[k,i,j,0]=d1[k,i,j,0]
                comp[k,i,j,1]=d1[k,i,j,1]
                comp[k,i,j,2]=d1[k,i,j,2]
                comp[k,i,j,0]+=alpha*beta*gamma*d2[kk,ii,jj,0]
                comp[k,i,j,1]+=alpha*beta*gamma*d2[kk,ii,jj,1]
                comp[k,i,j,2]+=alpha*beta*gamma*d2[kk,ii,jj,2]
                #---top-right
                jj+=1
                if(jj<nc2):
                    comp[k,i,j,0]+=alpha*cbeta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=alpha*cbeta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=alpha*cbeta*gamma*d2[kk,ii,jj,2]
                #---bottom-right
                ii+=1
                if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                    comp[k,i,j,0]+=calpha*cbeta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=calpha*cbeta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=calpha*cbeta*gamma*d2[kk,ii,jj,2]
                #---bottom-left
                jj-=1
                if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                    comp[k,i,j,0]+=calpha*beta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=calpha*beta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=calpha*beta*gamma*d2[kk,ii,jj,2]
                kk+=1
                if(kk<ns2):
                    ii-=1
                    comp[k,i,j,0]+=alpha*beta*cgamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=alpha*beta*cgamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=alpha*beta*cgamma*d2[kk,ii,jj,2]
                    jj+=1
                    if(jj<nc2):
                        comp[k,i,j,0]+=alpha*cbeta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=alpha*cbeta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=alpha*cbeta*cgamma*d2[kk,ii,jj,2]
                    #---bottom-right
                    ii+=1
                    if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                        comp[k,i,j,0]+=calpha*cbeta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=calpha*cbeta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=calpha*cbeta*cgamma*d2[kk,ii,jj,2]
                    #---bottom-left
                    jj-=1
                    if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                        comp[k,i,j,0]+=calpha*beta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=calpha*beta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=calpha*beta*cgamma*d2[kk,ii,jj,2]
                if((dkk>=0 and dkk<=ns2-1) and (dii>=0 and dii<=nr2-1) and (djj>=0 and djj<=nc2-1)):
                    nn=comp[k,i,j,0]*comp[k,i,j,0]+comp[k,i,j,1]*comp[k,i,j,1]+comp[k,i,j,2]*comp[k,i,j,2]
                    if(maxNorm<nn):
                        maxNorm=nn
                    meanNorm+=nn
                    stdNorm+=nn*nn
                    cnt+=1
    meanNorm/=cnt
    stats[0]=sqrt(maxNorm)
    stats[1]=sqrt(meanNorm)
    stats[2]=sqrt(stdNorm/cnt - meanNorm*meanNorm)

def compose_vector_fields_3d(floating[:,:,:,:] d1, floating[:,:,:,:] d2):
    cdef floating[:,:,:,:] comp=np.zeros_like(d1)
    cdef floating[:] stats=np.zeros(shape=(3,), dtype=cython.typeof(d1[0,0,0,0]))
    __compose_vector_fields_3d(d1, d2, comp, stats)
    return comp, stats

def invert_vector_field_fixed_point(floating[:,:,:] d, integral[:] inverseShape, int maxIter, floating tolerance, floating[:,:,:] start=None):
    cdef int nr1=d.shape[0]
    cdef int nc1=d.shape[1]
    cdef int nr2=nr1
    cdef int nc2=nc1
    cdef int iter_count, current
    cdef floating difmag, mag
    cdef floating epsilon=0.25
    cdef floating error = 1 + tolerance
    if inverseShape!=None:
        nr2, nc2=inverseShape[0], inverseShape[1]
    cdef floating[:] stats=np.zeros(shape=(2,), dtype=cython.typeof(d[0,0,0]))
    cdef floating[:,:,:] invd=np.zeros_like(d)
    cdef floating[:,:,:] p, q
    cdef floating[:] substats = np.empty(shape = (3,), dtype=cython.typeof(d[0,0,0]))
    if start==None:
        new_temp=np.zeros(shape=(nr2,nc2,2), dtype=cython.typeof(d[0,0,0]))
    else:
        new_temp=np.array(start)
    temp=[new_temp, invd]
    current=0
    iter_count = 0
    while (iter_count < maxIter) and (tolerance < error):
        current = 1 - current
        p=temp[1-current]
        q=temp[current]#these arrays need to be typed, their type can not be resolved by the compiler when calling __compose_vector_fields
        __compose_vector_fields(q, d, p, substats)
        difmag=0
        error=0
        for i in range(nr2):
            for j in range(nc2):
                mag=sqrt(p[i,j,0]**2 + p[i,j,1]**2)
                p[i,j,0] = q[i,j,0] - epsilon * p[i,j,0]
                p[i,j,1] = q[i,j,1] - epsilon * p[i,j,1]
                error+=mag
                if(difmag<mag):
                    difmag=mag
        error/=(nr2*nc2)
        iter_count+=1
    if(current == 1):#then the last computation was stored at temp[0]
        invd[...]=temp[0][...]
    stats[0]=substats[1]
    stats[1]=iter_count
    return invd

def invert_vector_field_fixed_point_3d(floating[:,:,:,:] d, int[:] inverseShape, int maxIter, floating tolerance, floating[:,:,:,:] start=None):
    cdef int ns1=d.shape[0]
    cdef int nr1=d.shape[1]
    cdef int nc1=d.shape[2]
    cdef int ns2=ns1
    cdef int nr2=nr1
    cdef int nc2=nc1
    if inverseShape!=None:
        ns2, nr2, nc2=inverseShape[0], inverseShape[1], inverseShape[2]
    cdef floating[:] stats=np.empty(shape=(2,), dtype=cython.typeof(d[0,0,0,0]))
    cdef floating[:] substats=np.empty(shape=(3,), dtype=cython.typeof(d[0,0,0,0]))
    cdef floating[:,:,:,:] invd=np.ndarray((ns2, nr2, nc2, 3), dtype=cython.typeof(d[0,0,0,0]))
    cdef floating[:,:,:,:] p, q
    cdef floating error=1+tolerance
    cdef floating epsilon = 0.5
    cdef floating mag, difmag
    cdef int k, i, j, iter_count, current
    if start==None:
        temp_new = np.zeros(shape=(ns2, nr2, nc2, 3), dtype=cython.typeof(d[0,0,0,0]))
    else:
        temp_new = np.array(start)
    temp=[temp_new, invd]
    current = 0
    iter_count = 0
    while (iter_count < maxIter) and (tolerance < error):
        current = 1 - current
        p=temp[1-current]
        q=temp[current]#these arrays need to be typed, their type can not be resolved by the compiler when calling __compose_vector_fields
        __compose_vector_fields_3d(q, d, p, substats)
        difmag=0
        error=0
        for k in range(ns2):
            for i in range(nr2):
                for j in range(nc2):
                    mag=sqrt(p[k,i,j,0]**2 + p[k,i,j,1]**2 + p[k,i,j,2]**2)
                    p[k,i,j,0] = q[k,i,j,0] - epsilon * p[k,i,j,0]
                    p[k,i,j,1] = q[k,i,j,1] - epsilon * p[k,i,j,1]
                    p[k,i,j,2] = q[k,i,j,2] - epsilon * p[k,i,j,2]
                    error+=mag
                    if(difmag<mag):
                        difmag=mag
        error/=(ns2*nr2*nc2)
    if(current == 1):#then the last computation was stored at temp[0]
        invd=temp_new
    stats[0]=error
    stats[1]=iter_count
    return invd

def prepend_affine_to_displacement_field_2d(floating[:,:,:] d, floating[:,:] affine):
    if affine==None:
        return
    cdef int nrows=d.shape[0]
    cdef int ncols=d.shape[1]
    cdef int i,j
    for i in range(nrows):
        for j in range(ncols):
            d[i,j,0]+=__apply_affine_2d_x0(i,j,affine)-i
            d[i,j,1]+=__apply_affine_2d_x1(i,j,affine)-j

def prepend_affine_to_displacement_field_3d(floating[:,:,:,:] d, floating[:,:] affine):
    if affine==None:
        return
    cdef int nslices=d.shape[0]
    cdef int nrows=d.shape[1]
    cdef int ncols=d.shape[2]
    cdef int i,j,k
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                d[k,i,j,0]+=__apply_affine_3d_x0(k,i,j,affine)-k
                d[k,i,j,1]+=__apply_affine_3d_x1(k,i,j,affine)-i
                d[k,i,j,2]+=__apply_affine_3d_x2(k,i,j,affine)-j

def append_affine_to_displacement_field_2d(floating[:,:,:] d, floating[:,:] affine):
    if affine==None:
        return
    cdef int nrows=d.shape[0]
    cdef int ncols=d.shape[1]
    cdef floating dii, djj
    cdef int i,j
    for i in range(nrows):
        for j in range(ncols):
            dii=d[i,j,0]+i
            djj=d[i,j,1]+j
            d[i,j,0]=__apply_affine_2d_x0(dii,djj,affine)-i
            d[i,j,1]=__apply_affine_2d_x1(dii,djj,affine)-j
    
def append_affine_to_displacement_field_3d(floating[:,:,:,:] d, floating[:,:] affine):
    if affine==None:
        return
    cdef int nslices=d.shape[0]
    cdef int nrows=d.shape[1]
    cdef int ncols=d.shape[2]
    cdef floating dkk,dii,djj
    cdef int i,j,k
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                dkk=d[k,i,j,0]+k
                dii=d[k,i,j,1]+i
                djj=d[k,i,j,2]+j
                d[k,i,j,0]=__apply_affine_3d_x0(dkk,dii,djj,affine)-k
                d[k,i,j,1]=__apply_affine_3d_x1(dkk,dii,djj,affine)-i
                d[k,i,j,2]=__apply_affine_3d_x2(dkk,dii,djj,affine)-j

def upsample_displacement_field(floating[:,:,:] field, int[:] targetShape):
    cdef int nr=field.shape[0]
    cdef int nc=field.shape[1]
    cdef int nrows=targetShape[0]
    cdef int ncols=targetShape[1]
    cdef floating dii, djj
    cdef floating alpha, beta, calpha, cbeta
    cdef int i,j,ii,jj
    cdef floating[:,:,:] up = np.zeros(shape=(nrows, ncols,2), dtype=cython.typeof(field[0,0,0]))
    for i in range(nr):
        for j in range(nc):
            dii=0.5*i
            djj=0.5*j
            if((dii<0) or (djj<0) or (dii>nrows-1) or (djj>ncols-1)):#no one is affected
                continue
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii<0) or (jj<0) or (ii>=nrows) or (jj>=ncols)):#no one is affected
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            #---top-left
            up[i,j,0]+=alpha*beta*field[ii,jj,0]
            up[i,j,1]+=alpha*beta*field[ii,jj,1]
            #---top-right
            jj+=1
            if(jj<ncols):
                up[i,j,0]+=alpha*cbeta*field[ii,jj,0]
                up[i,j,1]+=alpha*cbeta*field[ii,jj,1]
            #---bottom-right
            ii+=1
            if((ii>=0) and (jj>=0) and (ii<nrows) and (jj<ncols)):
                up[i,j,0]+=calpha*cbeta*field[ii,jj,0]
                up[i,j,1]+=calpha*cbeta*field[ii,jj,1]
            #---bottom-left
            jj-=1
            if((ii>=0) and (jj>=0) and (ii<nrows) and (jj<ncols)):
                up[i,j,0]+=calpha*beta*field[ii,jj,0]
                up[i,j,1]+=calpha*beta*field[ii,jj,1]
    return up

def upsample_displacement_field3D(floating[:,:,:,:] field, int[:] targetShape):
    cdef int ns=field.shape[0]
    cdef int nr=field.shape[1]
    cdef int nc=field.shape[2]
    cdef int nslices=targetShape[0]
    cdef int nrows=targetShape[1]
    cdef int ncols=targetShape[2]
    cdef int i,j,k,ii,jj,kk
    cdef floating dkk, dii, djj
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma
    cdef floating[:,:,:,:] up = np.zeros(shape=(nslices, nrows, ncols,3), dtype=cython.typeof(field[0,0,0,0]))
    for k in range(ns):
        for i in range(nr):
            for j in range(nc):
                dkk=0.5*k
                dii=0.5*i
                djj=0.5*j
                if((dkk<0) or (dii<0) or (djj<0) or (dii>nrows-1) or (djj>ncols-1) or (dkk>nslices-1)):#no one is affected
                    continue
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((kk<0) or (ii<0) or (jj<0) or (ii>=nrows) or (jj>=ncols) or (kk>=nslices)):#no one is affected
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                #---top-left
                up[k,i,j,0]+=alpha*beta*gamma*field[kk,ii,jj,0]
                up[k,i,j,1]+=alpha*beta*gamma*field[kk,ii,jj,1]
                up[k,i,j,2]+=alpha*beta*gamma*field[kk,ii,jj,2]
                #---top-right
                jj+=1
                if(jj<ncols):
                    up[k,i,j,0]+=alpha*cbeta*gamma*field[kk,ii,jj,0]
                    up[k,i,j,1]+=alpha*cbeta*gamma*field[kk,ii,jj,1]
                    up[k,i,j,2]+=alpha*cbeta*gamma*field[kk,ii,jj,2]
                #---bottom-right
                ii+=1
                if((ii>=0)and(jj>=0)and(ii<nrows)and(jj<ncols)):
                    up[k,i,j,0]+=calpha*cbeta*gamma*field[kk,ii,jj,0]
                    up[k,i,j,1]+=calpha*cbeta*gamma*field[kk,ii,jj,1]
                    up[k,i,j,2]+=calpha*cbeta*gamma*field[kk,ii,jj,2]
                #---bottom-left
                jj-=1
                if((ii>=0)and(jj>=0)and(ii<nrows)and(jj<ncols)):
                    up[k,i,j,0]+=calpha*beta*gamma*field[kk,ii,jj,0]
                    up[k,i,j,1]+=calpha*beta*gamma*field[kk,ii,jj,1]
                    up[k,i,j,2]+=calpha*beta*gamma*field[kk,ii,jj,2]
                kk+=1
                if(kk<nslices):
                    ii-=1
                    up[k,i,j,0]+=alpha*beta*cgamma*field[kk,ii,jj,0]
                    up[k,i,j,1]+=alpha*beta*cgamma*field[kk,ii,jj,1]
                    up[k,i,j,2]+=alpha*beta*cgamma*field[kk,ii,jj,2]
                    jj+=1
                    if(jj<ncols):
                        up[k,i,j,0]+=alpha*cbeta*cgamma*field[kk,ii,jj,0]
                        up[k,i,j,1]+=alpha*cbeta*cgamma*field[kk,ii,jj,1]
                        up[k,i,j,2]+=alpha*cbeta*cgamma*field[kk,ii,jj,2]
                    #---bottom-right
                    ii+=1
                    if((ii>=0)and(jj>=0)and(ii<nrows)and(jj<ncols)):
                        up[k,i,j,0]+=calpha*cbeta*cgamma*field[kk,ii,jj,0];
                        up[k,i,j,1]+=calpha*cbeta*cgamma*field[kk,ii,jj,1];
                        up[k,i,j,2]+=calpha*cbeta*cgamma*field[kk,ii,jj,2];
                    #---bottom-left
                    jj-=1
                    if((ii>=0)and(jj>=0)and(ii<nrows)and(jj<ncols)):
                        up[k,i,j,0]+=calpha*beta*cgamma*field[kk,ii,jj,0]
                        up[k,i,j,1]+=calpha*beta*cgamma*field[kk,ii,jj,1]
                        up[k,i,j,2]+=calpha*beta*cgamma*field[kk,ii,jj,2]
    return up

def get_displacement_range(floating[:,:,:,:] d, floating[:,:] affine):
    cdef int nslices=d.shape[0]
    cdef int nrows=d.shape[1]
    cdef int ncols=d.shape[2]
    cdef int i,j,k
    cdef floating dkk, dii, djj
    cdef floating[:] minVal = np.ndarray((3,), dtype=cython.typeof(d[0,0,0,0]))
    cdef floating[:] maxVal = np.ndarray((3,), dtype=cython.typeof(d[0,0,0,0]))
    minVal[...]=d[0,0,0,:]
    maxVal[...]=minVal[...]
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                if(affine!=None):
                    dkk=__apply_affine_3d_x0(k,i,j,affine)+d[k,i,j,0]
                    dii=__apply_affine_3d_x1(k,i,j,affine)+d[k,i,j,1]
                    djj=__apply_affine_3d_x2(k,i,j,affine)+d[k,i,j,2]
                else:
                    dkk=k+d[k,i,j,0]
                    dii=i+d[k,i,j,1]
                    djj=j+d[k,i,j,2]
                if(dkk>maxVal[0]):
                    maxVal[0]=dkk
                if(dii>maxVal[1]):
                    maxVal[1]=dii
                if(djj>maxVal[2]):
                    maxVal[2]=djj
    return minVal, maxVal

########################################################################
#############################volume warping#############################
########################################################################

def warp_volume(floating[:,:,:] volume, floating[:,:,:,:] d1, floating[:,:] affinePre=None, floating[:,:] affinePost=None):
    cdef int nslices=volume.shape[0]
    cdef int nrows=volume.shape[1]
    cdef int ncols=volume.shape[2]
    cdef int nsVol=volume.shape[0]
    cdef int nrVol=volume.shape[1]
    cdef int ncVol=volume.shape[2]
    cdef int i,j,k, ii, jj, kk
    cdef floating dkk, dii, djj, tmp0, tmp1
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma
    if d1!=None:
        nslices=d1.shape[0]
        nrows=d1.shape[1]
        ncols=d1.shape[2]
    cdef floating[:,:,:] warped = np.zeros(shape=(nslices, nrows, ncols), dtype=cython.typeof(volume[0,0,0]))
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                if(affinePre!=None):
                    dkk=__apply_affine_3d_x0(k,i,j,affinePre)+d1[k,i,j,0]
                    dii=__apply_affine_3d_x1(k,i,j,affinePre)+d1[k,i,j,1]
                    djj=__apply_affine_3d_x2(k,i,j,affinePre)+d1[k,i,j,2]
                else:
                    dkk=k+d1[k,i,j,0]
                    dii=i+d1[k,i,j,1]
                    djj=j+d1[k,i,j,2]
                if(affinePost!=None):
                    tmp0=__apply_affine_3d_x0(dkk,dii,djj,affinePost)
                    tmp1=__apply_affine_3d_x1(dkk,dii,djj,affinePost)
                    djj=__apply_affine_3d_x2(dkk,dii,djj,affinePost)
                    dii=tmp1
                    dkk=tmp0
                if((dii<0) or (djj<0) or (dkk<0) or (dii>nrVol-1) or (djj>ncVol-1) or (dkk>nsVol-1)):#no one is affected
                    continue
                #find the top left index and the interpolation coefficients
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                #---top-left
                warped[k,i,j]=alpha*beta*gamma*volume[kk,ii,jj]
                #---top-right
                jj+=1
                if(jj<ncVol):
                    warped[k,i,j]+=alpha*cbeta*gamma*volume[kk,ii,jj]
                #---bottom-right
                ii+=1
                if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                    warped[k,i,j]+=calpha*cbeta*gamma*volume[kk,ii,jj]
                #---bottom-left
                jj-=1
                if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                    warped[k,i,j]+=calpha*beta*gamma*volume[kk,ii,jj]
                kk+=1
                if(kk<nsVol):
                    ii-=1
                    warped[k,i,j]+=alpha*beta*cgamma*volume[kk,ii,jj]
                    jj+=1
                    if(jj<ncVol):
                        warped[k,i,j]+=alpha*cbeta*cgamma*volume[kk,ii,jj]
                    #---bottom-right
                    ii+=1
                    if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                        warped[k,i,j]+=calpha*cbeta*cgamma*volume[kk,ii,jj]
                    #---bottom-left
                    jj-=1
                    if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                        warped[k,i,j]+=calpha*beta*cgamma*volume[kk,ii,jj]
    return warped


def warp_volume_affine(floating[:,:,:] volume, int[:]refShape, floating[:,:] affine):
    cdef int nslices=refShape[0]
    cdef int nrows=refShape[1]
    cdef int ncols=refShape[2]
    cdef int nsVol=volume.shape[0]
    cdef int nrVol=volume.shape[1]
    cdef int ncVol=volume.shape[2]
    cdef int i,j,k, ii, jj, kk
    cdef floating dkk, dii, djj, tmp0, tmp1
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma
    cdef floating[:,:,:] warped = np.zeros(shape=(nslices, nrows, ncols), dtype=cython.typeof(volume[0,0,0]))
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                if(affine!=None):
                    dkk=__apply_affine_3d_x0(k,i,j,affine)
                    dii=__apply_affine_3d_x1(k,i,j,affine)
                    djj=__apply_affine_3d_x2(k,i,j,affine)
                else:
                    dkk=k
                    dii=i
                    djj=j
                if((dii<0) or (djj<0) or (dkk<0) or (dii>nrVol-1) or (djj>ncVol-1) or (dkk>nsVol-1)):#no one is affected
                    continue
                #find the top left index and the interpolation coefficients
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                #---top-left
                warped[k,i,j]=alpha*beta*gamma*volume[kk,ii,jj]
                #---top-right
                jj+=1
                if(jj<ncVol):
                    warped[k,i,j]+=alpha*cbeta*gamma*volume[kk,ii,jj]
                #---bottom-right
                ii+=1
                if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                    warped[k,i,j]+=calpha*cbeta*gamma*volume[kk,ii,jj]
                #---bottom-left
                jj-=1
                if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                    warped[k,i,j]+=calpha*beta*gamma*volume[kk,ii,jj]
                kk+=1
                if(kk<nsVol):
                    ii-=1
                    warped[k,i,j]+=alpha*beta*cgamma*volume[kk,ii,jj]
                    jj+=1
                    if(jj<ncVol):
                        warped[k,i,j]+=alpha*cbeta*cgamma*volume[kk,ii,jj]
                    #---bottom-right
                    ii+=1
                    if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                        warped[k,i,j]+=calpha*cbeta*cgamma*volume[kk,ii,jj]
                    #---bottom-left
                    jj-=1
                    if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                        warped[k,i,j]+=calpha*beta*cgamma*volume[kk,ii,jj]
    return warped

def warp_volume_nn(number[:,:,:] volume, floating[:,:,:,:] displacement, floating[:,:] affinePre=None, floating[:,:] affinePost=None):
    cdef int nslices=displacement.shape[0]
    cdef int nrows=displacement.shape[1]
    cdef int ncols=displacement.shape[2]
    cdef int nsVol=volume.shape[0]
    cdef int nrVol=volume.shape[1]
    cdef int ncVol=volume.shape[2]
    cdef floating dkk, dii, djj, tmp0, tmp1
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma
    cdef int k,i,j,kk,ii,jj
    cdef number[:,:,:] warped = np.ndarray((nslices, nrows, ncols), dtype=cython.typeof(volume[0,0,0]))
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                if(affinePre!=None):
                    dkk=__apply_affine_3d_x0(k,i,j,affinePre)+displacement[k,i,j,0]
                    dii=__apply_affine_3d_x1(k,i,j,affinePre)+displacement[k,i,j,1]
                    djj=__apply_affine_3d_x2(k,i,j,affinePre)+displacement[k,i,j,2]
                else:
                    dkk=k+displacement[k,i,j,0]
                    dii=i+displacement[k,i,j,1]
                    djj=j+displacement[k,i,j,2]
                if(affinePost!=None):
                    tmp0=__apply_affine_3d_x0(dkk,dii,djj,affinePost)
                    tmp1=__apply_affine_3d_x1(dkk,dii,djj,affinePost)
                    djj=__apply_affine_3d_x2(dkk,dii,djj,affinePost)
                    dii=tmp1
                    dkk=tmp0
                if((dii<0) or (djj<0) or (dkk<0) or (dii>nrVol-1) or (djj>ncVol-1) or (dkk>nsVol-1)):#no one is affected
                    continue
                #find the top left index and the interpolation coefficients
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                if(gamma<cgamma):
                    kk+=1
                if(alpha<calpha):
                    ii+=1
                if(beta<cbeta):
                    jj+=1
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                else:
                    warped[k,i,j]=volume[kk,ii,jj]
    return warped

def warp_volume_affine_nn(number[:,:,:] volume, int[:]refShape, floating[:,:] affine=None):
    cdef int nslices=refShape[0]
    cdef int nrows=refShape[1]
    cdef int ncols=refShape[2]
    cdef int nsVol=volume.shape[0]
    cdef int nrVol=volume.shape[1]
    cdef int ncVol=volume.shape[2]
    cdef floating dkk, dii, djj, tmp0, tmp1
    cdef floating alpha, beta, gamma, calpha, cbeta, cgamma
    cdef int k,i,j,kk,ii,jj
    cdef number[:,:,:] warped = np.ndarray((nslices, nrows, ncols), dtype=cython.typeof(volume[0,0,0]))
    for k in range(nslices):
        for i in range(nrows):
            for j in range(ncols):
                if(affine!=None):
                    dkk=__apply_affine_3d_x0(k,i,j,affine)
                    dii=__apply_affine_3d_x1(k,i,j,affine)
                    djj=__apply_affine_3d_x2(k,i,j,affine)
                else:
                    dkk=k
                    dii=i
                    djj=j
                if((dii<0) or (djj<0) or (dkk<0) or (dii>nrVol-1) or (djj>ncVol-1) or (dkk>nsVol-1)):#no one is affected
                    continue
                #find the top left index and the interpolation coefficients
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                if(gamma<cgamma):
                    kk+=1
                if(alpha<calpha):
                    ii+=1
                if(beta<cbeta):
                    jj+=1
                if((ii<0) or (jj<0) or (kk<0) or (ii>=nrVol) or (jj>=ncVol) or (kk>=nsVol)):#no one is affected
                    continue
                else:
                    warped[k,i,j]=volume[kk,ii,jj]
    return warped


########################################################################
#############################image warping##############################
########################################################################

def warp_image(floating[:,:] image, floating[:,:,:] d1, floating[:,:] affinePre=None, floating[:,:] affinePost=None):
    cdef int nrows=image.shape[0]
    cdef int ncols=image.shape[1]
    cdef int nrVol=image.shape[0]
    cdef int ncVol=image.shape[1]
    cdef int i,j, ii, jj
    cdef floating dii, djj, tmp0
    cdef floating alpha, beta, calpha, cbeta
    if d1!=None:
        nrows=d1.shape[0]
        ncols=d1.shape[1]
    cdef floating[:,:] warped = np.zeros(shape=(nrows, ncols), dtype=cython.typeof(image[0,0]))
    for i in range(nrows):
        for j in range(ncols):
            if(affinePre!=None):
                dii=__apply_affine_2d_x0(i,j,affinePre)+d1[i,j,0]
                djj=__apply_affine_2d_x1(i,j,affinePre)+d1[i,j,1]
            else:
                dii=i+d1[i,j,0]
                djj=j+d1[i,j,1]
            if(affinePost!=None):
                tmp0=__apply_affine_2d_x0(dii,djj,affinePost)
                djj=__apply_affine_2d_x1(dii,djj,affinePost)
                dii=tmp0
            if((dii<0) or (djj<0) or (dii>nrVol-1) or (djj>ncVol-1)):#no one is affected
                continue
            #find the top left index and the interpolation coefficients
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            #---top-left
            warped[i,j]=alpha*beta*image[ii,jj]
            #---top-right
            jj+=1
            if(jj<ncVol):
                warped[i,j]+=alpha*cbeta*image[ii,jj]
            #---bottom-right
            ii+=1
            if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                warped[i,j]+=calpha*cbeta*image[ii,jj]
            #---bottom-left
            jj-=1
            if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                warped[i,j]+=calpha*beta*image[ii,jj]
    return warped


def warp_image_affine(floating[:,:] image, int[:]refShape, floating[:,:] affine=None):
    cdef int nrows=refShape[0]
    cdef int ncols=refShape[1]
    cdef int nrVol=image.shape[0]
    cdef int ncVol=image.shape[1]
    cdef int i,j, ii, jj
    cdef floating dii, djj, tmp0
    cdef floating alpha, beta, calpha, cbeta
    cdef floating[:,:] warped = np.zeros(shape=(nrows, ncols), dtype=cython.typeof(image[0,0]))
    for i in range(nrows):
        for j in range(ncols):
            if(affine!=None):
                dii=__apply_affine_2d_x0(i,j,affine)
                djj=__apply_affine_2d_x1(i,j,affine)
            else:
                dii=i
                djj=j
            if((dii<0) or (djj<0) or (dii>nrVol-1) or (djj>ncVol-1)):#no one is affected
                continue
            #find the top left index and the interpolation coefficients
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            #---top-left
            warped[i,j]=alpha*beta*image[ii,jj]
            #---top-right
            jj+=1
            if(jj<ncVol):
                warped[i,j]+=alpha*cbeta*image[ii,jj]
            #---bottom-right
            ii+=1
            if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                warped[i,j]+=calpha*cbeta*image[ii,jj]
            #---bottom-left
            jj-=1
            if((ii>=0) and (jj>=0) and (ii<nrVol) and (jj<ncVol)):
                warped[i,j]+=calpha*beta*image[ii,jj]
    return warped

def warp_image_nn(number[:,:] image, floating[:,:,:] displacement, floating[:,:] affinePre=None, floating[:,:] affinePost=None):
    cdef int nrows=image.shape[0]
    cdef int ncols=image.shape[1]
    cdef int nrVol=image.shape[0]
    cdef int ncVol=image.shape[1]
    cdef floating dii, djj, tmp0
    cdef floating alpha, beta, calpha, cbeta
    cdef int i,j,ii,jj
    if displacement!=None:
        nrows=displacement.shape[0]
        ncols=displacement.shape[1]
    cdef number[:,:] warped = np.ndarray((nrows, ncols), dtype=cython.typeof(image[0,0]))
    for i in range(nrows):
        for j in range(ncols):
            if(affinePre!=None):
                dii=__apply_affine_2d_x0(i,j,affinePre)+displacement[i,j,0]
                djj=__apply_affine_2d_x1(i,j,affinePre)+displacement[i,j,1]
            else:
                dii=i+displacement[i,j,0]
                djj=j+displacement[i,j,1]
            if(affinePost!=None):
                tmp0=__apply_affine_2d_x0(dii,djj,affinePost)
                djj=__apply_affine_2d_x1(dii,djj,affinePost)
                dii=tmp0
            if((dii<0) or (djj<0) or (dii>nrVol-1) or (djj>ncVol-1)):#no one is affected
                continue
            #find the top left index and the interpolation coefficients
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            if(alpha<calpha):
                ii+=1
            if(beta<cbeta):
                jj+=1
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            else:
                warped[i,j]=image[ii,jj]
    return warped

def warp_image_affine_nn(number[:,:] image, int[:]refShape, floating[:,:] affine=None):
    cdef int nrows=refShape[0]
    cdef int ncols=refShape[1]
    cdef int nrVol=image.shape[0]
    cdef int ncVol=image.shape[1]
    cdef floating dii, djj, tmp0
    cdef floating alpha, beta, calpha, cbeta
    cdef int i,j,ii,jj
    cdef number[:,:] warped = np.ndarray((nrows, ncols), dtype=cython.typeof(image[0,0]))
    for i in range(nrows):
        for j in range(ncols):
            if(affine!=None):
                dii=__apply_affine_2d_x0(i,j,affine)
                djj=__apply_affine_2d_x1(i,j,affine)
            else:
                dii=i
                djj=j
            if((dii<0) or (djj<0) or (dii>nrVol-1) or (djj>ncVol-1)):#no one is affected
                continue
            #find the top left index and the interpolation coefficients
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            calpha=dii-ii#by definition these factors are nonnegative
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            if(alpha<calpha):
                ii+=1
            if(beta<cbeta):
                jj+=1
            if((ii<0) or (jj<0) or (ii>=nrVol) or (jj>=ncVol)):#no one is affected
                continue
            else:
                warped[i,j]=image[ii,jj]
    return warped


