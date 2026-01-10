## First principles: do we need an API server? 

Currently the fomo architecture does _not_ use an api server. There are a few reasons for this, but primarily operational overhead and cost. Since it doesn't need anything to be "real time", the architecture can afford to be server-less and "eventually consistent". Meaning it is totally fine if a write somewhere followed by a read elsewhere within the span of a few seconds returns missing data (i.e. the files that were just written don't show up). Our users are quite tolerant to such delays. 

### Why now, then? 

Some key reasons for an api server. Think of these not within the scope of say a photomon but within the scope of photomon and plantwise. 

1. Consolidate user/data handling: currently all the logic to connect users and data lives in the client. Typically we would have multiple  "apps" or surfaces through which our users interact with their data (and other datasets on the platform). In order to not reimplement the entire stack once in each client, we will think of common user/auth/data applications and centralize them in an api server. 

2. Development Scalability: while this is a non standard reason, it is an important one. We can make the initial cut of plantwise, but down the line we may want to hand this off to a vendor. We would still want the features to work the same way, and manage the data, the licensing, the sharing etc. This needs a consistent API. We wouldn't want the vendor to eg inadvertently wipe out photomon data. 

3. AWS decoupling: when clients write directly to s3, they embed the api logic in the app. If we ever need to move away from s3 for unpredictable reasons, doing so would be difficult. 

4. Triggers: it seems likely that program admins would want to know when interesting datasets have been uploaded, eg via push notifications. While it is possible to add pipeline scripts/cron jobs that poll s3, it can quickly get difficult for a small team to manage a distribute set of scripts. An API server is just a way to organize this. The most likely use case here is a trigger to a OCR service for form ingestion. 


### And a few made up but plausible reasons 
 
5. Finer grained users and roles: we might want to show eg  different sites for different user profiles, say a RA and a BFE. In the current architecture we would either have to embed this logic in the app or write out different config files into s3.

6. Pagination: in low bandwidth environments, as the number of sites grow we might want pagination (i.e. to not download the entire sites file)


