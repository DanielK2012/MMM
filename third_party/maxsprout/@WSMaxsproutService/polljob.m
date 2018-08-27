function result = polljob(obj,jobid,outformat)
%polljob(obj,jobid,outformat)
%
%   Deprecated
%   
%     Input:
%       jobid = (string)
%       outformat = (string)
%   
%     Output:
%       result = (base64Binary)

% Build up the argument lists.
values = { ...
   jobid, ...
   outformat, ...
   };
names = { ...
   'jobid', ...
   'outformat', ...
   };
types = { ...
   '{http://www.w3.org/2001/XMLSchema}string', ...
   '{http://www.w3.org/2001/XMLSchema}string', ...
   };

% Create the message, make the call, and convert the response into a variable.
soapMessage = createSoapMessage( ...
    'http://www.ebi.ac.uk/WSMaxsprout', ...
    'polljob', ...
    values,names,types,'rpc');
response = callSoapService( ...
    obj.endpoint, ...
    'http://www.ebi.ac.uk/WSMaxsprout#polljob', ...
    soapMessage);
result = parseSoapResponse(response);
