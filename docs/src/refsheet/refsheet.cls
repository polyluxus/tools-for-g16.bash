%&tex
\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{refsheet}[2018/08/29 v1.0 Reference Sheet Class]

%%% OPTION DEFINITIONS
%
%   Simple definitions for key-value pairs with kvoptions
%   See J. Wright, C. Feuersänger, TUGBoat, Vol. 30 (2009), No. 1, p. 110-122
%
\RequirePackage{kvoptions}
\SetupKeyvalOptions{
  family=refsheet,
  prefix=refsheet@
}
%
%   Defining how many columns shall be used, 3 is the initial value,
%   which can be set with rscols=<int> in the preamble.
%   Disable this option for the body of the document.
%
\DeclareStringOption[3]{rscols}
\AtBeginDocument{%
  \DisableKeyvalOption[action=error,package=refsheet]{refsheet}{rscols}}
%
%   Define a preset margin for geometry
%
\DeclareStringOption[1cm]{margin}
%
%   Warn about options which will not be used/ passed on because of potential clashes
%
\DeclareVoidOption{portrait}{%
  \PackageWarning{refsheet}{Incompatible with portrait mode}}
\DeclareVoidOption{twocolumn}{%
  \PackageError{refsheet}{Using 'multicol' for columns}}
\DeclareVoidOption{titlepage}{%
  \PackageWarning{refsheet}{Incompatible with a title page}}
%
%   Pass all other options to article
%
\DeclareDefaultOption{%
  \PassOptionsToClass{\CurrentOptionKey}{article}}
%
%   DEV: Space for more options
%

%
%   Process these options
%   
\ProcessKeyvalOptions{refsheet}
%
%%%

%%% INHERIT STANDARD CLASS
%
%   Latest update of standard class article
%   (It probably also works with earlier versions, but why sweat it.)
\LoadClass{article}[2014/09/29]
%
%%%

%%% ADDITIONAL REQUIRED TOOLS
%
%   Latest update of the nag package. 
%   Harasses the user about deprecated usages.
%
\RequirePackage[orthodox,l2tabu,abort]{nag}[2011/11/25] 
%
%   Package etoolbox is necessary for additional hooks like \AtEndPreamble
%
\RequirePackage{etoolbox}
%
%   Page layout with latest version of geometry
%
\RequirePackage{geometry}[2018/04/16]
\AtEndPreamble{%
  \geometry{landscape,margin=\refsheet@margin}}
%
%   Produce columns with multicol
%
\RequirePackage{multicol}[2018/04/20]
\AfterEndPreamble{%
  \begin{multicols}{\refsheet@rscols}}
\AtEndDocument{%
  \end{multicols}}
%
%%%

%%% REDEFINE TITLE
%
\renewcommand{\maketitle}{%
  {%
   \begin{center}%
     \Large \@title \\%
     \vspace{0.1ex}%
     \small \@author, \@date\end{center}%
  }%
}
%
%%%

%%% DOCUMENT DIVISIONS
%
%   Package titlesec for setting spacing
%
\RequirePackage{titlesec}
%
%   Package nopageno so there are no page numbers
%   (to keep \section from resetting page style).
%
\RequirePackage{nopageno} 
%
%   No section numbering
%
\setcounter{secnumdepth}{0}
%
%   No indentation and superfluous spacing
%
\setlength{\parindent}{0pt} 
\titlespacing{\section}{0pt}{0pt}{0pt}
\titlespacing{\subsection}{0pt}{0pt}{0pt}
%
%%%

%%% COMMANDS AND ENVIRONMENTS
%
%   Extended definition of lists with enumitem
%
\RequirePackage[inline]{enumitem}[2011/08/28]
%   Calculating widths, e.g. with \widthof
\RequirePackage{calc} 

% generate dense lists
\setlist{noitemsep,topsep=0.05ex,}
\setlist[itemize]{label=\textendash,leftmargin=*}
\setlist[description]{leftmargin=!}
% Provide a list-type for truetype descriptions
% This is retained for backward compatibility
\newlist{ttdesc}{description}{1}
\setlist[ttdesc]{font=\ttfamily}
% Conveniently assigning the longest label as 
\newenvironment{rslisttt}[1]
{
  \begin{description}[labelwidth=\widthof{\texttt{#1}},font=\ttfamily]
}{
  \end{description}
}

% Provide a list-type for normal descriptions
\newenvironment{rslist}[1]
{
    \begin{description}[labelwidth=\widthof{#1}]
}{
    \end{description}
}

% Provide a list-type for bold descriptions
\newenvironment{rslistbf}[1]
{
    \begin{description}[labelwidth=\widthof{\textbf{#1}},font=\bfseries]
}{
    \end{description}
}

% Provide a list-type for italic descriptions
\newenvironment{rslistit}[1]
{
    \begin{description}[labelwidth=\widthof{\textit{#1}},font=\itshape]
}{
    \end{description}
}

% Provide inline description lists
\newenvironment{rsinline}[1][\ttfamily]
{
  \begin{description*}[font={#1}]
}{
    \end{description*}
}

% Provide column list
\newenvironment{rscolslist}[1][2]
{
  \begin{multicols*}{#1}
    \begin{itemize*}[itemjoin={{\newline}},afterlabel={\nobreakspace}]
}{
    \end{itemize*}
  \end{multicols*}
}


% Provide an easier interface to create a table
\RequirePackage{tabularx}

% Full width table with automagic column widths
\newcounter{rstablecols}
\newenvironment{rstable}[2][X]
{
  \setcounter{rstablecols}{#2}
  \addtocounter{rstablecols}{-1}

  \tabularx{\linewidth}{ *{\value{rstablecols}}{#1} X }%
}{
  \endtabularx
  \setcounter{rstablecols}{0}
}

\newenvironment{rsmathtable}
{
  \tabularx{\linewidth}{ >{\(\displaystyle}l<{\)} X }%
}{
  \endtabularx
}

