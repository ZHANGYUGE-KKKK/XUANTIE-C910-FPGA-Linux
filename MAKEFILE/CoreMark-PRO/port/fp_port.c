/*
(C) 2014 EEMBC(R).  All rights reserved.                            

All EEMBC Benchmark Software are products of EEMBC 
and are provided under the terms of the EEMBC Benchmark License Agreements.  
The EEMBC Benchmark Software are proprietary intellectual properties of EEMBC and its Members 
and is protected under all applicable laws, including all applicable copyright laws.  
If you received this EEMBC Benchmark Software without having 
a currently effective EEMBC Benchmark License Agreement, you must discontinue use. 
Please refer to LICENSE.md for the specific license agreement that pertains to this Benchmark Software.
*/
/* IEEE floating-point conversions copied unchanged from the upstream AL. */
#include "th_lib.h"
#include "th_al.h"
#include "fp_shape.h"

int store_dp(e_f64 *value, intparts *asint)
{
   e_f64 v64;
   e_u32 iexp;
   e_s32 exp=asint->exp;
   e_u32 manthigh=asint->mant_high32;

   if (manthigh >= ((e_u32)1<<(52-32 + 1)))
   {
      return 0;
   }
   if (!(manthigh & ((e_u32)1<<(52-32))))
   {
      /* special casing signed zero */
      if (exp ==0 && asint->mant_low32 == 0 && manthigh == 0)
      {
		INSERT_WORDS(v64, (e_u32)(asint->sign) << 31, 0);
        *value = v64;
        return 1;
      }
      return 0;
   }

   manthigh &= ((e_u32)1 << (52-32)) - 1;

   exp += 1023;
   if (exp <= 0 || exp >= 2047)
   {
      return 0;
   }
   iexp = exp << (52-32);
   if (asint->sign)
   {
      iexp |= 0x80000000;
   }
   INSERT_WORDS(v64, (manthigh | iexp), asint->mant_low32);
   *value = v64;
   return 1;
}

/* supports denorm, no inf/nan */
int load_dp(e_f64 *value, intparts *asint)
{
   e_u32 iValue0, iValue1;

   if (!value || !asint)
      return 0;

   EXTRACT_WORDS(iValue1, iValue0, *value);

   asint->mant_low32 = iValue0;
   asint->mant_high32 = (iValue1 & (((e_u32)1 << (52 - 32)) - 1));
   asint->exp = ((iValue1 >> (52-32)) & 2047);
   asint->sign = iValue1 >> 31;

   if (asint->exp == 2047)
      return 0;

   if (asint->exp != 0)
   {
      asint->mant_high32 |=  ((e_u32)1 << (52-32));
      asint->exp -= 1023;
   }
   else
   {
      if (asint->mant_high32 || asint->mant_low32)
         return 0;
   }
   return 1;
}

/* no denormal/inf/nan support */
int store_sp(e_f32 *value, intparts *asint)
{
   e_u32 iValue;
   e_f32 v32;
   e_u32 iexp;
   e_s32 exp=asint->exp;
   e_u32 mant=asint->mant_low32;

   if (asint->mant_high32)
      return 0;

   if (mant >= ((e_u32)1<<24))
   {
      return 0;
   }
   if (!(mant & ((e_u32)1<<23)))
   {
      /* special casing signed zero */
      if (exp == 0 && mant == 0)
      {
         iValue = (e_u32)(asint->sign) << 31;
         SET_FLOAT_WORD(v32, iValue);
         *value = v32;
         return 1;
      }
      return 0;
   }

   mant &= ((e_u32)1 << 23) - 1;

   exp += 127;
   if (exp <= 0 || exp >= 255)
   {
      return 0;
   }
   iexp = exp << 23;
   if (asint->sign)
   {
      iexp |= 0x80000000;
   }
   iValue = mant | iexp; 
   SET_FLOAT_WORD(v32, iValue);
   *value = v32;
   return 1;
}

int load_sp(e_f32 *value, intparts *asint)
{
   e_u32 iValue;

   if (!value || !asint)
      return 0;

   GET_FLOAT_WORD(iValue, *value);

   asint->mant_high32 = 0;
   asint->mant_low32 = (iValue & (((e_u32)1 << 23) - 1));
   asint->exp = ((iValue >> 23) & 255);

   if (asint->exp == 255)
      return 0;

   if (asint->exp != 0)
   {
      asint->mant_low32 |=  ((e_u32)1 << 23);
      asint->exp -= 127;
   }
   else
   {
      if (asint->mant_low32)
         return 0;
   }
   asint->sign = iValue >> 31;
   return 1;
}

